using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;

namespace SpanShot
{
    public enum ScrollDirection
    {
        Vertical = 0,   // Top-to-Bottom scrolling (content moves up)
        Horizontal = 1  // Left-to-Right scrolling (content moves left)
    }

    public enum StitchStatus
    {
        FirstFrame,
        NoMovement,
        Stitched,
        ScrolledBackward,
        LowConfidence,
        MaxLengthReached
    }

    public struct StitchResult
    {
        public StitchStatus Status;
        public int DeltaPixels;
        public double Confidence;
        public int TotalLength;
        public int FrameCount;
        public int DetectedStickyHead;
        public int DetectedStickyTail;
    }

    /// <summary>
    /// High-precision 1D+2D hybrid image stitching engine for both Vertical and Horizontal scrolling captures.
    /// Specifically hardened for complex enterprise tables (Element UI, Ant Design, Excel, Feishu):
    /// 1. Supports wide frozen left columns / sticky headers up to 70% of capture width/height.
    /// 2. Cross-axis active band isolation (BuildActiveCrossBinMask): automatically isolates the scrolling table rows
    ///    even when the user's selection includes static top toolbars, static bottom summary rows ("合计:"), or opposite-moving scrollbars.
    /// 3. Scroll-axis derivative filtering & TextComplexity weighting (24x over periodic grid lines).
    /// 4. Minimum-energy seam cutting (FindCleanSeamSlice).
    /// </summary>
    public sealed class StitchEngine : IDisposable
    {
        private const int SAMPLE_COUNT = 64;
        private const int SCROLLBAR_MARGIN = 18;
        private const int LEADING_BORDER_MARGIN = 6;
        private const int MAX_CANVAS_LENGTH = 30000;

        private readonly ScrollDirection _direction;
        private NormalizedFrame _prevFrame;
        private Bitmap _prevBitmap;

        private readonly List<CanvasStrip> _strips = new List<CanvasStrip>();
        private readonly Stack<HistorySnapshot> _undoStack = new Stack<HistorySnapshot>();

        private int _crossDimension;
        private int _primaryFrameDimension;
        private int _globalOffset;
        private int _totalCanvasLength;
        private int _frameCount;
        private int _runningStickyHead;
        private int _runningStickyTail;
        private bool[] _runningCrossMask;
        private int _consecutiveLowConfidence;
        private NormalizedFrame _lastUnmatchedFrame;
        private Bitmap _lastUnmatchedBitmap;

        private struct CanvasStrip
        {
            public int GlobalStart;
            public int Length;
            public Bitmap Bitmap;
            public int SrcOffset;
        }

        private struct HistorySnapshot
        {
            public int StripCountBefore;
            public int LastStripLengthBefore;
            public int GlobalOffsetBefore;
            public int TotalCanvasLengthBefore;
            public int FrameCountBefore;
            public Bitmap PrevBitmapClone;
        }

        private sealed class NormalizedFrame
        {
            public int PrimaryLen;
            public int CrossLen;
            public byte[][] LumaSamples;      // [PrimaryLen][SAMPLE_COUNT] box-averaged luma
            public byte[][] PeakContrast;     // [PrimaryLen][SAMPLE_COUNT] max-min contrast inside bin
            public byte[][] ScrollGrad;       // [PrimaryLen][SAMPLE_COUNT] |Luma[p][k] - Luma[p-1][k]| along scroll axis
            public short[][] ChromaSamples;   // [PrimaryLen][SAMPLE_COUNT] color signature
            public int[] EdgeEnergy;          // [PrimaryLen] scroll-axis edge energy (ignores parallel grid lines)
            public int[] TextComplexity;      // [PrimaryLen] high for text/characters, low for uniform grid lines or whitespace
            public ulong[] RowHash;           // [PrimaryLen] 64-bit perceptual hash
        }

        public ScrollDirection Direction { get { return _direction; } }
        public int TotalCanvasLength { get { return _totalCanvasLength; } }
        public int CrossDimension { get { return _crossDimension; } }
        public int FrameCount { get { return _frameCount; } }
        public bool CanUndo { get { return _undoStack.Count > 0; } }

        public StitchEngine(ScrollDirection direction)
        {
            _direction = direction;
        }

        public void Reset()
        {
            ClearUndoStack();
            if (_prevBitmap != null)
            {
                _prevBitmap.Dispose();
                _prevBitmap = null;
            }
            _prevFrame = null;
            for (int i = 0; i < _strips.Count; i++)
            {
                if (_strips[i].Bitmap != null) _strips[i].Bitmap.Dispose();
            }
            _strips.Clear();
            _globalOffset = 0;
            _totalCanvasLength = 0;
            _frameCount = 0;
            _runningStickyHead = 0;
            _runningStickyTail = 0;
            _runningCrossMask = null;
            _consecutiveLowConfidence = 0;
            ClearLastUnmatched();
        }

        private void ClearLastUnmatched()
        {
            _lastUnmatchedFrame = null;
            if (_lastUnmatchedBitmap != null)
            {
                _lastUnmatchedBitmap.Dispose();
                _lastUnmatchedBitmap = null;
            }
        }

        public bool UndoLastFrame()
        {
            if (_undoStack.Count == 0) return false;
            ClearLastUnmatched();

            HistorySnapshot snap = _undoStack.Pop();

            while (_strips.Count > snap.StripCountBefore)
            {
                int lastIdx = _strips.Count - 1;
                if (_strips[lastIdx].Bitmap != null)
                {
                    _strips[lastIdx].Bitmap.Dispose();
                }
                _strips.RemoveAt(lastIdx);
            }

            if (_strips.Count > 0)
            {
                int lastIdx = _strips.Count - 1;
                CanvasStrip s = _strips[lastIdx];
                s.Length = snap.LastStripLengthBefore;
                _strips[lastIdx] = s;
            }

            _globalOffset = snap.GlobalOffsetBefore;
            _totalCanvasLength = snap.TotalCanvasLengthBefore;
            _frameCount = snap.FrameCountBefore;

            if (_prevBitmap != null) _prevBitmap.Dispose();
            _prevBitmap = snap.PrevBitmapClone;
            _prevFrame = ExtractNormalizedFrame(_prevBitmap, _direction);

            return true;
        }

        private void ClearUndoStack()
        {
            while (_undoStack.Count > 0)
            {
                HistorySnapshot s = _undoStack.Pop();
                if (s.PrevBitmapClone != null) s.PrevBitmapClone.Dispose();
            }
        }

        public StitchResult PushFrame(Bitmap frame)
        {
            if (frame == null) throw new ArgumentNullException("frame");

            NormalizedFrame norm = ExtractNormalizedFrame(frame, _direction);

            if (_prevFrame == null)
            {
                _prevFrame = norm;
                _prevBitmap = (Bitmap)frame.Clone();
                _primaryFrameDimension = norm.PrimaryLen;
                _crossDimension = norm.CrossLen;
                _globalOffset = 0;
                _totalCanvasLength = norm.PrimaryLen;
                _frameCount = 1;

                _strips.Add(new CanvasStrip
                {
                    GlobalStart = 0,
                    Length = norm.PrimaryLen,
                    Bitmap = (Bitmap)frame.Clone(),
                    SrcOffset = 0
                });

                return new StitchResult
                {
                    Status = StitchStatus.FirstFrame,
                    DeltaPixels = 0,
                    Confidence = 1.0,
                    TotalLength = _totalCanvasLength,
                    FrameCount = _frameCount
                };
            }

            if (norm.PrimaryLen != _primaryFrameDimension || norm.CrossLen != _crossDimension)
            {
                throw new InvalidOperationException("Frame dimensions must remain constant during a scrolling capture session.");
            }

            if (_totalCanvasLength >= MAX_CANVAS_LENGTH)
            {
                return new StitchResult
                {
                    Status = StitchStatus.MaxLengthReached,
                    DeltaPixels = 0,
                    Confidence = 1.0,
                    TotalLength = _totalCanvasLength,
                    FrameCount = _frameCount
                };
            }

            // 1. Check whether any sub-region of the frame has moved (supports tables where 50%+ is frozen/static)
            double zeroDiff;
            if (!HasFrameMoved(_prevFrame, norm, out zeroDiff))
            {
                return new StitchResult
                {
                    Status = StitchStatus.NoMovement,
                    DeltaPixels = 0,
                    Confidence = 1.0 - (zeroDiff / 255.0),
                    TotalLength = _totalCanvasLength,
                    FrameCount = _frameCount,
                    DetectedStickyHead = _runningStickyHead,
                    DetectedStickyTail = _runningStickyTail
                };
            }

            // 2. Build initial cross-axis active bin mask from the trailing scrollable portion of the frame
            bool foundInitialBins;
            bool[] initialCrossMask = BuildActiveCrossBinMask(
                _prevFrame, norm, (norm.PrimaryLen * 52) / 100, (norm.PrimaryLen * 95) / 100, _runningCrossMask, out foundInitialBins);

            // 3. Strict Sticky Header / Frozen Left Column (up to 68% of frame!) & Sticky Footer detection
            int maxHead = (norm.PrimaryLen * 68) / 100;
            int maxTail = (norm.PrimaryLen * 28) / 100;

            int detectedHead = DetectStickyHeadStrict(_prevFrame, norm, maxHead, initialCrossMask);
            int detectedTail = DetectStickyTailStrict(_prevFrame, norm, maxTail, initialCrossMask);

            int candidateStickyHead = _runningStickyHead;
            if (candidateStickyHead == 0 && detectedHead >= 16)
            {
                candidateStickyHead = detectedHead;
            }
            else if (candidateStickyHead > 0 && detectedHead >= 16)
            {
                if (detectedHead < candidateStickyHead)
                {
                    candidateStickyHead = detectedHead;
                }
                else if (_frameCount <= 2 && detectedHead > candidateStickyHead)
                {
                    candidateStickyHead = detectedHead;
                }
            }

            int candidateStickyTail = _runningStickyTail;
            if (detectedTail >= 8)
            {
                if (candidateStickyTail == 0 || detectedTail < candidateStickyTail || Math.Abs(detectedTail - candidateStickyTail) <= 30)
                {
                    candidateStickyTail = candidateStickyTail == 0 ? detectedTail : Math.Min(candidateStickyTail, detectedTail);
                }
                else if (_frameCount <= 2 && detectedTail > candidateStickyTail)
                {
                    candidateStickyTail = detectedTail;
                }
            }

            int activeStart = Math.Min(maxHead, Math.Max(4, candidateStickyHead + (candidateStickyHead > 0 ? 4 : 0)));
            int activeEnd = norm.PrimaryLen - Math.Min(maxTail, Math.Max(4, candidateStickyTail + (candidateStickyTail > 0 ? 4 : 0)));
            int activeLen = activeEnd - activeStart;

            if (activeLen < 40)
            {
                activeStart = 6;
                activeEnd = norm.PrimaryLen - 6;
                activeLen = activeEnd - activeStart;
            }

            // Refine the active cross-axis bin mask specifically inside [activeStart .. activeEnd]
            bool foundActiveBins;
            bool[] activeCrossMask = BuildActiveCrossBinMask(_prevFrame, norm, activeStart, activeEnd, _runningCrossMask, out foundActiveBins);

            // 4. Coarse-to-Fine search for scroll offset delta
            int minDelta = 5;
            int maxDelta = Math.Max(minDelta + 1, (activeLen * 80) / 100);

            int bestDelta;
            double bestScore;
            bool isBackward;
            bool isNoMovement;
            bool matched = FindBestScrollDelta(
                _prevFrame, norm, _prevBitmap, frame,
                activeStart, activeEnd, minDelta, maxDelta, activeCrossMask,
                out bestDelta, out bestScore, out isBackward, out isNoMovement);

            if (isNoMovement)
            {
                return new StitchResult
                {
                    Status = StitchStatus.NoMovement,
                    DeltaPixels = 0,
                    Confidence = bestScore,
                    TotalLength = _totalCanvasLength,
                    FrameCount = _frameCount,
                    DetectedStickyHead = _runningStickyHead,
                    DetectedStickyTail = _runningStickyTail
                };
            }

            if (isBackward)
            {
                return new StitchResult
                {
                    Status = StitchStatus.ScrolledBackward,
                    DeltaPixels = bestDelta,
                    Confidence = bestScore,
                    TotalLength = _totalCanvasLength,
                    FrameCount = _frameCount,
                    DetectedStickyHead = _runningStickyHead,
                    DetectedStickyTail = _runningStickyTail
                };
            }

            if (!matched || bestDelta < minDelta)
            {
                // If the user scrolled faster than a single viewport overlap (> 80% of activeLen),
                // check if the new frame matches cleanly against the intermediate unmatched frame!
                if (_lastUnmatchedFrame != null && _lastUnmatchedBitmap != null)
                {
                    int bridgeDelta;
                    double bridgeScore;
                    bool bridgeBack;
                    bool bridgeNoMove;
                    bool bridgeMatched = FindBestScrollDelta(
                        _lastUnmatchedFrame, norm, _lastUnmatchedBitmap, frame,
                        activeStart, activeEnd, minDelta, maxDelta, activeCrossMask,
                        out bridgeDelta, out bridgeScore, out bridgeBack, out bridgeNoMove);

                    if (bridgeMatched && bridgeDelta >= minDelta && bridgeScore >= 0.78)
                    {
                        int safeRight = _prevFrame.PrimaryLen - (_prevFrame.PrimaryLen >= 200 ? 24 : 6);
                        int bridgeCut = Math.Min(activeEnd, safeRight);
                        int bridgeConfirmedEnd = _globalOffset + bridgeCut;
                        int bridgeCopyLen = _lastUnmatchedFrame.PrimaryLen - activeStart;
                        if (bridgeConfirmedEnd + bridgeCopyLen > MAX_CANVAS_LENGTH)
                        {
                            bridgeCopyLen = Math.Max(0, MAX_CANVAS_LENGTH - bridgeConfirmedEnd);
                        }

                        if (bridgeCopyLen > 0)
                        {
                            TrimStripsBeyond(bridgeConfirmedEnd);
                            _strips.Add(new CanvasStrip
                            {
                                GlobalStart = bridgeConfirmedEnd,
                                Length = bridgeCopyLen,
                                Bitmap = (Bitmap)_lastUnmatchedBitmap.Clone(),
                                SrcOffset = activeStart
                            });
                            _globalOffset = bridgeConfirmedEnd - activeStart;
                            _totalCanvasLength = bridgeConfirmedEnd + bridgeCopyLen;
                            _frameCount++;
                        }

                        _prevBitmap.Dispose();
                        _prevBitmap = (Bitmap)_lastUnmatchedBitmap.Clone();
                        _prevFrame = _lastUnmatchedFrame;
                        ClearLastUnmatched();

                        bestDelta = bridgeDelta;
                        bestScore = bridgeScore;
                        matched = true;
                    }
                }

                if (!matched || bestDelta < minDelta)
                {
                    _consecutiveLowConfidence++;
                    double moveFromLastUnmatched = 0.0;
                    if (_lastUnmatchedFrame == null || HasFrameMoved(_lastUnmatchedFrame, norm, out moveFromLastUnmatched))
                    {
                        ClearLastUnmatched();
                        _lastUnmatchedFrame = norm;
                        _lastUnmatchedBitmap = (Bitmap)frame.Clone();
                    }
                    return new StitchResult
                    {
                        Status = StitchStatus.LowConfidence,
                        DeltaPixels = 0,
                        Confidence = bestScore,
                        TotalLength = _totalCanvasLength,
                        FrameCount = _frameCount,
                        DetectedStickyHead = _runningStickyHead,
                        DetectedStickyTail = _runningStickyTail
                    };
                }
            }

            _consecutiveLowConfidence = 0;
            ClearLastUnmatched();
            _runningStickyHead = candidateStickyHead;
            _runningStickyTail = candidateStickyTail;
            if (foundActiveBins)
            {
                if (_runningCrossMask == null) _runningCrossMask = new bool[SAMPLE_COUNT];
                for (int k = 0; k < SAMPLE_COUNT; k++)
                {
                    if (activeCrossMask[k]) _runningCrossMask[k] = true;
                }
            }

            // 5. Minimum-Energy Seam Selection (FindCleanSeamSlice)
            int cleanCutInPrev = FindCleanSeamSlice(_prevFrame, norm, activeStart, activeEnd, bestDelta, activeCrossMask);

            int confirmedEnd = _globalOffset + cleanCutInPrev;
            int newGlobalOffset = _globalOffset + bestDelta;
            int srcStartInCurr = confirmedEnd - newGlobalOffset;

            if (srcStartInCurr < 0) srcStartInCurr = 0;
            int copyLen = norm.PrimaryLen - srcStartInCurr;

            if (confirmedEnd + copyLen > MAX_CANVAS_LENGTH)
            {
                copyLen = Math.Max(0, MAX_CANVAS_LENGTH - confirmedEnd);
            }

            if (copyLen > 0)
            {
                if (_undoStack.Count < 15 && _strips.Count > 0)
                {
                    _undoStack.Push(new HistorySnapshot
                    {
                        StripCountBefore = _strips.Count,
                        LastStripLengthBefore = _strips[_strips.Count - 1].Length,
                        GlobalOffsetBefore = _globalOffset,
                        TotalCanvasLengthBefore = _totalCanvasLength,
                        FrameCountBefore = _frameCount,
                        PrevBitmapClone = (Bitmap)_prevBitmap.Clone()
                    });
                }

                TrimStripsBeyond(confirmedEnd);

                _strips.Add(new CanvasStrip
                {
                    GlobalStart = confirmedEnd,
                    Length = copyLen,
                    Bitmap = (Bitmap)frame.Clone(),
                    SrcOffset = srcStartInCurr
                });

                _globalOffset = newGlobalOffset;
                _totalCanvasLength = confirmedEnd + copyLen;
                _frameCount++;
            }

            _prevBitmap.Dispose();
            _prevBitmap = (Bitmap)frame.Clone();
            _prevFrame = norm;

            return new StitchResult
            {
                Status = StitchStatus.Stitched,
                DeltaPixels = bestDelta,
                Confidence = bestScore,
                TotalLength = _totalCanvasLength,
                FrameCount = _frameCount,
                DetectedStickyHead = activeStart,
                DetectedStickyTail = norm.PrimaryLen - activeEnd
            };
        }

        private static bool HasFrameMoved(NormalizedFrame prev, NormalizedFrame curr, out double zeroDiff)
        {
            int start = prev.PrimaryLen / 12;
            int end = (prev.PrimaryLen * 11) / 12;
            double sum = 0.0;
            int count = 0;
            int movedSlices = 0;

            for (int s = start; s < end; s++)
            {
                double d = SliceDifference(prev, s, curr, s, null);
                sum += d;
                count++;

                if (d > 1.1)
                {
                    movedSlices++;
                    continue;
                }

                // Also check if a localized cross-axis sub-band moved (e.g., header-only or single-row table)
                byte[] lumaA = prev.LumaSamples[s];
                byte[] lumaB = curr.LumaSamples[s];
                byte[] peakA = prev.PeakContrast[s];
                byte[] peakB = curr.PeakContrast[s];
                byte[] gradA = prev.ScrollGrad[s];
                byte[] gradB = curr.ScrollGrad[s];
                int changedBins = 0;
                for (int k = 2; k < SAMPLE_COUNT - 3; k++)
                {
                    int rawDl = Math.Abs(lumaA[k] - lumaB[k]);
                    int dl = (lumaA[k] > 236 && lumaB[k] > 236) ? Math.Max(0, rawDl - 10) : Math.Max(0, rawDl - 3);
                    int dp = Math.Max(0, Math.Abs(peakA[k] - peakB[k]) - 9);
                    int dg = Math.Abs(gradA[k] - gradB[k]);
                    int binDiff = dl + dp + dg;
                    if (binDiff > 11 || dg > 9)
                    {
                        changedBins++;
                        if (changedBins >= 2 || binDiff > 22 || dg > 16)
                        {
                            movedSlices++;
                            break;
                        }
                    }
                }
            }

            zeroDiff = count > 0 ? sum / count : 0.0;
            return zeroDiff >= 1.1 || movedSlices >= 5;
        }

        /// <summary>
        /// Identifies which cross-axis bins [0..SAMPLE_COUNT-1] actually changed between prev and curr.
        /// This isolates the scrolling table body and header from static top toolbars (e.g. "+ 添加行 / 删除"),
        /// static bottom summary rows ("合计:"), and opposite-moving scrollbar thumbs.
        /// </summary>
        private static bool[] BuildActiveCrossBinMask(
            NormalizedFrame prev, NormalizedFrame curr, int startSlice, int endSlice, bool[] runningMask, out bool foundActiveBins)
        {
            int span = Math.Max(1, endSlice - startSlice);
            int[] changedSliceCount = new int[SAMPLE_COUNT];
            int[] edgesPrev = new int[SAMPLE_COUNT];
            int[] edgesCurr = new int[SAMPLE_COUNT];

            for (int s = startSlice; s < endSlice; s++)
            {
                byte[] lA = prev.LumaSamples[s];
                byte[] lB = curr.LumaSamples[s];
                byte[] pA = prev.PeakContrast[s];
                byte[] pB = curr.PeakContrast[s];
                byte[] gA = prev.ScrollGrad[s];
                byte[] gB = curr.ScrollGrad[s];

                for (int k = 1; k < SAMPLE_COUNT - 2; k++)
                {
                    if (gA[k] >= 6) edgesPrev[k]++;
                    if (gB[k] >= 6) edgesCurr[k]++;

                    int rawDl = Math.Abs(lA[k] - lB[k]);
                    int dl = (lA[k] > 236 && lB[k] > 236) ? Math.Max(0, rawDl - 10) : Math.Max(0, rawDl - 3);
                    int dp = Math.Max(0, Math.Abs(pA[k] - pB[k]) - 9);
                    int dg = Math.Abs(gA[k] - gB[k]);
                    int diff = dl + dp + dg;
                    if (diff > 7)
                    {
                        changedSliceCount[k]++;
                    }
                }
            }

            int[] minEdges = new int[SAMPLE_COUNT];
            int peakEdges = 0;
            for (int k = 1; k < SAMPLE_COUNT - 2; k++)
            {
                minEdges[k] = Math.Min(edgesPrev[k], edgesCurr[k]);
                if (minEdges[k] > peakEdges) peakEdges = minEdges[k];
            }

            int threshold = Math.Max(3, span / 60);
            int minEdgeReq = Math.Max(5, peakEdges / 11);
            bool[] rawMask = new bool[SAMPLE_COUNT];
            int activeCount = 0;

            for (int k = 1; k < SAMPLE_COUNT - 2; k++)
            {
                // Require minEdges[k] >= minEdgeReq to isolate true text/feature rows and reject 2-edge scrollbar thumbs
                if (changedSliceCount[k] >= threshold && minEdges[k] >= minEdgeReq)
                {
                    rawMask[k] = true;
                    activeCount++;
                }
            }

            foundActiveBins = activeCount >= 1;

            if (!foundActiveBins && runningMask == null)
            {
                bool[] all = new bool[SAMPLE_COUNT];
                for (int k = 1; k < SAMPLE_COUNT - 3; k++) all[k] = true;
                return all;
            }

            // Dilate by 1 bin into neighbors that also have genuine scroll-axis edges (never into scrollbar thumbs)
            bool[] dilated = new bool[SAMPLE_COUNT];
            for (int k = 1; k < SAMPLE_COUNT - 2; k++)
            {
                if (rawMask[k] ||
                    (minEdges[k] >= 5 && ((k > 1 && rawMask[k - 1]) || (k + 1 < SAMPLE_COUNT - 2 && rawMask[k + 1]))))
                {
                    dilated[k] = true;
                }
                else if (runningMask != null && runningMask[k] && minEdges[k] >= 1)
                {
                    dilated[k] = true;
                }
            }

            int finalCount = 0;
            for (int k = 0; k < SAMPLE_COUNT; k++)
            {
                if (dilated[k]) finalCount++;
            }

            if (finalCount == 0 && runningMask != null)
            {
                return (bool[])runningMask.Clone();
            }

            return dilated;
        }

        private static int FindCleanSeamSlice(NormalizedFrame prev, NormalizedFrame curr, int activeStart, int activeEnd, int delta, bool[] crossMask)
        {
            int overlapStartInPrev = activeStart + delta;
            int safeRightLimit = prev.PrimaryLen - (prev.PrimaryLen >= 200 ? 24 : 6);
            int maxCut = (safeRightLimit > overlapStartInPrev + 8) ? Math.Min(activeEnd, safeRightLimit) : activeEnd;

            int searchWindow = Math.Min(44, (maxCut - overlapStartInPrev) / 2);
            if (searchWindow <= 2) return maxCut;

            int searchStart = Math.Max(overlapStartInPrev + 4, maxCut - searchWindow);
            int bestSlice = maxCut - 1;
            double bestSeamCost = double.MaxValue;

            for (int sPrev = searchStart; sPrev < maxCut; sPrev++)
            {
                int sCurr = sPrev - delta;
                if (sCurr < activeStart || sCurr >= curr.PrimaryLen) continue;

                double diff = SliceDifference(prev, sPrev, curr, sCurr, crossMask);
                double gradPenalty = (prev.EdgeEnergy[sPrev] + curr.EdgeEnergy[sCurr]) * 0.45;
                double textPenalty = (prev.TextComplexity[sPrev] + curr.TextComplexity[sCurr]) * 0.35;

                double seamCost = diff * 2.0 + gradPenalty + textPenalty;
                if (seamCost < bestSeamCost)
                {
                    bestSeamCost = seamCost;
                    bestSlice = sPrev;
                }
            }

            return bestSlice;
        }

        private void TrimStripsBeyond(int confirmedEnd)
        {
            for (int i = _strips.Count - 1; i >= 0; i--)
            {
                CanvasStrip strip = _strips[i];
                int stripEnd = strip.GlobalStart + strip.Length;
                if (strip.GlobalStart >= confirmedEnd)
                {
                    strip.Bitmap.Dispose();
                    _strips.RemoveAt(i);
                }
                else if (stripEnd > confirmedEnd)
                {
                    strip.Length = confirmedEnd - strip.GlobalStart;
                    _strips[i] = strip;
                }
                else
                {
                    break;
                }
            }
        }

        public Bitmap RenderStitchedBitmap()
        {
            if (_strips.Count == 0) return null;

            int width = _direction == ScrollDirection.Vertical ? _crossDimension : _totalCanvasLength;
            int height = _direction == ScrollDirection.Vertical ? _totalCanvasLength : _crossDimension;

            Bitmap result = new Bitmap(width, height, PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(result))
            {
                g.CompositingMode = CompositingMode.SourceCopy;
                for (int i = 0; i < _strips.Count; i++)
                {
                    CanvasStrip s = _strips[i];
                    if (s.Length <= 0) continue;

                    if (_direction == ScrollDirection.Vertical)
                    {
                        Rectangle destRect = new Rectangle(0, s.GlobalStart, _crossDimension, s.Length);
                        Rectangle srcRect = new Rectangle(0, s.SrcOffset, _crossDimension, s.Length);
                        g.DrawImage(s.Bitmap, destRect, srcRect, GraphicsUnit.Pixel);
                    }
                    else
                    {
                        Rectangle destRect = new Rectangle(s.GlobalStart, 0, s.Length, _crossDimension);
                        Rectangle srcRect = new Rectangle(s.SrcOffset, 0, s.Length, _crossDimension);
                        g.DrawImage(s.Bitmap, destRect, srcRect, GraphicsUnit.Pixel);
                    }
                }
            }
            return result;
        }

        public Bitmap RenderPreviewThumbnail(int boxW, int boxH)
        {
            if (_strips.Count == 0 || boxW <= 20 || boxH <= 20) return null;

            int fullW = _direction == ScrollDirection.Vertical ? _crossDimension : _totalCanvasLength;
            int fullH = _direction == ScrollDirection.Vertical ? _totalCanvasLength : _crossDimension;

            double scale = Math.Min(1.0, Math.Min((double)boxW / fullW, (double)boxH / fullH));
            int thumbW = Math.Max(1, (int)Math.Round(fullW * scale));
            int thumbH = Math.Max(1, (int)Math.Round(fullH * scale));

            Bitmap thumb = new Bitmap(thumbW, thumbH, PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(thumb))
            {
                g.InterpolationMode = InterpolationMode.Bilinear;
                DrawScaledCanvas(g, 0, 0, thumbW, thumbH, scale);
            }
            return thumb;
        }

        private void DrawScaledCanvas(Graphics g, int offsetX, int offsetY, int thumbW, int thumbH, double scale)
        {
            for (int i = 0; i < _strips.Count; i++)
            {
                CanvasStrip s = _strips[i];
                if (s.Length <= 0) continue;

                if (_direction == ScrollDirection.Vertical)
                {
                    int dy0 = offsetY + (int)Math.Round(s.GlobalStart * scale);
                    int dy1 = offsetY + (int)Math.Round((s.GlobalStart + s.Length) * scale);
                    int dh = Math.Max(1, dy1 - dy0);
                    Rectangle destRect = new Rectangle(offsetX, dy0, thumbW, dh);
                    Rectangle srcRect = new Rectangle(0, s.SrcOffset, _crossDimension, s.Length);
                    g.DrawImage(s.Bitmap, destRect, srcRect, GraphicsUnit.Pixel);
                }
                else
                {
                    int dx0 = offsetX + (int)Math.Round(s.GlobalStart * scale);
                    int dx1 = offsetX + (int)Math.Round((s.GlobalStart + s.Length) * scale);
                    int dw = Math.Max(1, dx1 - dx0);
                    Rectangle destRect = new Rectangle(dx0, offsetY, dw, thumbH);
                    Rectangle srcRect = new Rectangle(s.SrcOffset, 0, s.Length, _crossDimension);
                    g.DrawImage(s.Bitmap, destRect, srcRect, GraphicsUnit.Pixel);
                }
            }
        }

        private static int MaxActiveBinDiff(NormalizedFrame prev, int sa, NormalizedFrame curr, int sb, bool[] crossMask)
        {
            byte[] lA = prev.LumaSamples[sa];
            byte[] lB = curr.LumaSamples[sb];
            byte[] pA = prev.PeakContrast[sa];
            byte[] pB = curr.PeakContrast[sb];
            byte[] gA = prev.ScrollGrad[sa];
            byte[] gB = curr.ScrollGrad[sb];

            int maxDiff = 0;
            for (int k = 1; k < SAMPLE_COUNT - 2; k++)
            {
                if (crossMask != null && !crossMask[k]) continue;
                int rawDl = Math.Abs(lA[k] - lB[k]);
                int dl = (lA[k] > 236 && lB[k] > 236) ? Math.Max(0, rawDl - 10) : Math.Max(0, rawDl - 3);
                int dp = Math.Max(0, Math.Abs(pA[k] - pB[k]) - 8);
                int dg = Math.Abs(gA[k] - gB[k]);
                int binDiff = dl + dp + dg;
                if (binDiff > maxDiff) maxDiff = binDiff;
            }
            return maxDiff;
        }

        private static int DetectStickyHeadStrict(NormalizedFrame prev, NormalizedFrame curr, int maxHead, bool[] crossMask)
        {
            bool[] sliceMovedArr = new bool[maxHead];
            bool[] statTextArr = new bool[maxHead];
            int totalStatCount = 0;
            int totalStatTextSlices = 0;
            int lastStatTextClusterSlice = 0;

            for (int s = 0; s < maxHead; s++)
            {
                double diff = SliceDifference(prev, s, curr, s, crossMask);
                int maxBinDiff = MaxActiveBinDiff(prev, s, curr, s, crossMask);
                bool sliceMoved = (maxBinDiff >= 18 && diff > 1.8) || (diff > 3.4);
                sliceMovedArr[s] = sliceMoved;

                if (!sliceMoved)
                {
                    totalStatCount++;
                    if (prev.TextComplexity[s] >= 2 && curr.TextComplexity[s] >= 2)
                    {
                        statTextArr[s] = true;
                        totalStatTextSlices++;

                        // Check if this slice belongs to a genuine stationary text cluster (>= 5 text slices in 24px window)
                        // while the prefix [0..s] is predominantly stationary (>= 72%)
                        int recentText = 0;
                        for (int j = Math.Max(0, s - 23); j <= s; j++)
                        {
                            if (statTextArr[j]) recentText++;
                        }
                        if (recentText >= 5 && totalStatCount * 100 >= (s + 1) * 72)
                        {
                            lastStatTextClusterSlice = s + 1;
                        }
                    }
                }
            }

            int lastTransitionSlice = lastStatTextClusterSlice;
            int stationaryTextSlices = totalStatTextSlices;
            int startScan = (lastStatTextClusterSlice >= 24) ? Math.Max(0, lastStatTextClusterSlice - 4) : 0;

            int movingBurstCount = 0;
            int gapSlices = 0;
            int firstMovingSlice = -1;

            for (int s = startScan; s < maxHead; s++)
            {
                if (!sliceMovedArr[s])
                {
                    if (movingBurstCount > 0)
                    {
                        gapSlices++;
                        if (gapSlices > 3)
                        {
                            movingBurstCount = 0;
                            gapSlices = 0;
                            firstMovingSlice = -1;
                        }
                    }

                    if (movingBurstCount == 0)
                    {
                        if ((prev.EdgeEnergy[s] >= 2 && curr.EdgeEnergy[s] >= 2) ||
                            (stationaryTextSlices >= 6 && prev.EdgeEnergy[s] >= 1 && curr.EdgeEnergy[s] >= 1))
                        {
                            lastTransitionSlice = Math.Max(lastTransitionSlice, s + 1);
                        }
                    }
                }
                else
                {
                    if (firstMovingSlice < 0) firstMovingSlice = s;
                    movingBurstCount++;
                    gapSlices = 0;

                    if (movingBurstCount >= 6)
                    {
                        int moveStart = firstMovingSlice;
                        if (stationaryTextSlices >= 8 && moveStart >= 32 && moveStart - lastTransitionSlice <= 24)
                        {
                            // Genuine frozen header/column with stationary text, followed by subtle shadow before moving content
                            lastTransitionSlice = Math.Max(lastTransitionSlice, moveStart - 2);
                        }
                        else if (stationaryTextSlices >= 8 && lastTransitionSlice == lastStatTextClusterSlice && moveStart > lastTransitionSlice)
                        {
                            lastTransitionSlice = Math.Min(moveStart - 2, lastStatTextClusterSlice + 18);
                        }
                        else if (moveStart >= 12 && SliceMeanLumaDifference(prev, 0, moveStart - 1) < 1.5 &&
                                 Math.Abs(SliceMeanLuma(prev, moveStart / 2) - SliceMeanLuma(prev, Math.Min(prev.PrimaryLen - 1, moveStart + 20))) > 12.0)
                        {
                            lastTransitionSlice = moveStart;
                        }
                        break;
                    }
                }
            }

            return lastTransitionSlice >= 8 ? lastTransitionSlice : 0;
        }

        private static int DetectStickyTailStrict(NormalizedFrame prev, NormalizedFrame curr, int maxTail, bool[] crossMask)
        {
            int len = prev.PrimaryLen;
            int lastTransitionTail = 0;
            int stationaryTextSlices = 0;

            for (int i = 0; i < maxTail; i++)
            {
                int s = len - 1 - i;
                double diff = SliceDifference(prev, s, curr, s, crossMask);
                if (diff <= 1.8)
                {
                    if (prev.TextComplexity[s] >= 2 && curr.TextComplexity[s] >= 2)
                    {
                        stationaryTextSlices++;
                    }
                    // Outermost 22px can be a scrollbar/border; deeper than 22px requires genuine stationary text or solid fill transition
                    if (prev.EdgeEnergy[s] >= 2 && curr.EdgeEnergy[s] >= 2 && (i < 22 || stationaryTextSlices >= 4))
                    {
                        lastTransitionTail = i + 1;
                    }
                }
                else
                {
                    if (i >= 10 && SliceMeanLumaDifference(prev, len - 1, s + 1) < 1.5 &&
                        Math.Abs(SliceMeanLuma(prev, len - 1 - i / 2) - SliceMeanLuma(prev, Math.Max(0, s - 20))) > 12.0)
                    {
                        lastTransitionTail = i;
                    }
                    break;
                }
            }

            return lastTransitionTail >= 8 ? lastTransitionTail : 0;
        }

        private static double SliceMeanLuma(NormalizedFrame f, int s)
        {
            byte[] luma = f.LumaSamples[s];
            int sum = 0;
            for (int i = 0; i < SAMPLE_COUNT; i++) sum += luma[i];
            return (double)sum / SAMPLE_COUNT;
        }

        private static double SliceMeanLumaDifference(NormalizedFrame f, int s1, int s2)
        {
            return Math.Abs(SliceMeanLuma(f, s1) - SliceMeanLuma(f, s2));
        }

        private static int FindActiveMaskMidpoint(bool[] crossMask)
        {
            if (crossMask == null) return SAMPLE_COUNT / 2;
            int first = -1;
            int last = -1;
            for (int k = 0; k < SAMPLE_COUNT; k++)
            {
                if (crossMask[k])
                {
                    if (first < 0) first = k;
                    last = k;
                }
            }
            return (first >= 0 && last > first + 3) ? ((first + last) / 2) : (SAMPLE_COUNT / 2);
        }

        private bool FindBestScrollDelta(
            NormalizedFrame prev, NormalizedFrame curr,
            Bitmap prevBmp, Bitmap currBmp,
            int activeStart, int activeEnd,
            int minDelta, int maxDelta,
            bool[] activeCrossMask,
            out int bestDelta, out double bestConfidence, out bool isBackward, out bool isNoMovement)
        {
            bestDelta = 0;
            bestConfidence = 0.0;
            isBackward = false;
            isNoMovement = false;

            int activeLen = activeEnd - activeStart;
            int midBin = FindActiveMaskMidpoint(activeCrossMask);

            long totalEnergy = 0;
            long totalTextComp = 0;
            for (int s = activeStart; s < activeEnd; s++)
            {
                totalEnergy += prev.EdgeEnergy[s];
                totalTextComp += prev.TextComplexity[s];
            }
            int meanEnergy = (int)Math.Max(4, totalEnergy / Math.Max(1, activeLen));
            int meanTextComp = (int)Math.Max(4, totalTextComp / Math.Max(1, activeLen));

            const int TOP_K = 14;
            int[] topDeltas = new int[TOP_K];
            double[] topCosts = new double[TOP_K];
            for (int i = 0; i < TOP_K; i++) topCosts[i] = double.MaxValue;

            for (int delta = minDelta; delta <= maxDelta; delta++)
            {
                int overlapStartInPrev = activeStart + delta;
                int overlapLen = activeEnd - overlapStartInPrev;
                if (overlapLen < 28) break;

                double cost = Evaluate1DCandidate(prev, curr, activeStart, activeEnd, delta, meanEnergy, meanTextComp, activeCrossMask, midBin);

                if (cost < topCosts[TOP_K - 1])
                {
                    bool updated = false;
                    for (int k = 0; k < TOP_K; k++)
                    {
                        if (topDeltas[k] > 0 && Math.Abs(topDeltas[k] - delta) <= 5)
                        {
                            if (cost < topCosts[k])
                            {
                                topCosts[k] = cost;
                                topDeltas[k] = delta;
                                SortTopK(topDeltas, topCosts);
                            }
                            updated = true;
                            break;
                        }
                    }
                    if (!updated)
                    {
                        topCosts[TOP_K - 1] = cost;
                        topDeltas[TOP_K - 1] = delta;
                        SortTopK(topDeltas, topCosts);
                    }
                }
            }

            // Stage 2: High-density 2D pixel + scroll-gradient + multi-band verification on Top-K candidates
            double best2DCost = double.MaxValue;
            int verifiedDelta = 0;

            for (int k = 0; k < TOP_K; k++)
            {
                int candDelta = topDeltas[k];
                if (candDelta < minDelta) continue;

                for (int offset = -3; offset <= 3; offset++)
                {
                    int d = candDelta + offset;
                    if (d < minDelta || d > maxDelta) continue;

                    double pixelError = VerifyCandidate2DPixels(
                        prev, curr, prevBmp, currBmp, activeStart, activeEnd, d, meanEnergy, meanTextComp, activeCrossMask, midBin);

                    double adjustedCost = pixelError + (d * 0.0035);

                    if (adjustedCost < best2DCost)
                    {
                        best2DCost = adjustedCost;
                        verifiedDelta = d;
                    }
                }
            }

            // Guard against zero-movement hover/focus changes and subpixel settling (< minDelta) inside the scrollable region (prevents duplicate stitching!)
            double zero2DCost = double.MaxValue;
            int maxZeroCheck = Math.Min(4, minDelta - 1);
            for (int zd = 0; zd <= maxZeroCheck; zd++)
            {
                double zc = VerifyCandidate2DPixels(prev, curr, prevBmp, currBmp, activeStart, activeEnd, zd, meanEnergy, meanTextComp, activeCrossMask, midBin);
                if (zc < zero2DCost) zero2DCost = zc;
            }

            if (zero2DCost < 2.0 || zero2DCost <= best2DCost * 0.96)
            {
                isNoMovement = true;
                bestConfidence = Math.Max(0.0, 1.0 - (zero2DCost / 40.0));
                return false;
            }

            // Check for accidental backward scroll (delta < 0)
            if (best2DCost > 1.8)
            {
                int maxBack = Math.Min(160, activeLen / 2);
                double bestBack1DCost = double.MaxValue;
                int bestBackDelta = 0;

                for (int backDelta = -minDelta; backDelta >= -maxBack; backDelta--)
                {
                    double backCost = Evaluate1DCandidate(curr, prev, activeStart, activeEnd, -backDelta, meanEnergy, meanTextComp, activeCrossMask, midBin);
                    if (backCost < bestBack1DCost)
                    {
                        bestBack1DCost = backCost;
                        bestBackDelta = backDelta;
                    }
                }

                if (bestBackDelta < 0 && bestBack1DCost + 2.0 < topCosts[0])
                {
                    double back2DErr = VerifyCandidate2DPixels(
                        curr, prev, currBmp, prevBmp, activeStart, activeEnd, -bestBackDelta, meanEnergy, meanTextComp, activeCrossMask, midBin);

                    if (back2DErr < 6.0 && back2DErr + 2.5 < best2DCost)
                    {
                        isBackward = true;
                        bestDelta = bestBackDelta;
                        bestConfidence = Math.Max(0.0, 1.0 - (back2DErr / 40.0));
                        return false;
                    }
                }
            }

            if (verifiedDelta < minDelta || best2DCost > 24.0)
            {
                bestConfidence = Math.Max(0.0, 1.0 - (best2DCost / 64.0));
                return false;
            }

            bestDelta = verifiedDelta;
            bestConfidence = Math.Max(0.0, Math.Min(1.0, 1.0 - (best2DCost / 40.0)));
            return true;
        }

        private static double Evaluate1DCandidate(
            NormalizedFrame prev, NormalizedFrame curr,
            int activeStart, int activeEnd, int delta, int meanEnergy, int meanTextComp, bool[] crossMask, int midBin)
        {
            int overlapStartInPrev = activeStart + delta;
            int overlapLen = activeEnd - overlapStartInPrev;
            if (overlapLen < 24) return 255.0;

            double weightedDiffSum = 0.0;
            double weightSum = 0.0;
            double textDiffSum = 0.0;
            int textSliceCount = 0;
            double band0WeightedSum = 0.0;
            double band0WeightSum = 0.0;
            double band1WeightedSum = 0.0;
            double band1WeightSum = 0.0;
            int bothFeatureSlices = 0;
            int exactHashMatches = 0;

            for (int sPrev = overlapStartInPrev; sPrev < activeEnd; sPrev++)
            {
                int sCurr = sPrev - delta;

                if (prev.RowHash[sPrev] == curr.RowHash[sCurr] && prev.TextComplexity[sPrev] > meanTextComp / 2)
                {
                    exactHashMatches++;
                }

                bool prevHasFeat = prev.TextComplexity[sPrev] >= meanTextComp / 2 || prev.EdgeEnergy[sPrev] >= meanEnergy;
                bool currHasFeat = curr.TextComplexity[sCurr] >= meanTextComp / 2 || curr.EdgeEnergy[sCurr] >= meanEnergy;
                if (prevHasFeat && currHasFeat)
                {
                    bothFeatureSlices++;
                }

                double b0SliceErr, b1SliceErr;
                int b0Edges, b1Edges;
                double d = SliceBandDifference(prev, sPrev, curr, sCurr, crossMask, midBin, out b0SliceErr, out b0Edges, out b1SliceErr, out b1Edges);

                if (b0Edges > 0)
                {
                    double bw0 = 1.0 + b0Edges * 2.5;
                    band0WeightedSum += b0SliceErr * bw0;
                    band0WeightSum += bw0;
                }
                if (b1Edges > 0)
                {
                    double bw1 = 1.0 + b1Edges * 2.5;
                    band1WeightedSum += b1SliceErr * bw1;
                    band1WeightSum += bw1;
                }

                double structDiff = (Math.Abs(prev.EdgeEnergy[sPrev] - curr.EdgeEnergy[sCurr])
                                   + Math.Abs(prev.TextComplexity[sPrev] - curr.TextComplexity[sCurr])) * 0.06;
                double totalSliceCost = d + structDiff;

                int energy = Math.Max(prev.EdgeEnergy[sPrev], curr.EdgeEnergy[sCurr]);
                int textComp = Math.Max(prev.TextComplexity[sPrev], curr.TextComplexity[sCurr]);

                double w = 1.0
                         + Math.Min(8.0, (double)energy / meanEnergy * 2.0)
                         + Math.Min(24.0, (double)textComp / meanTextComp * 8.0);

                weightedDiffSum += totalSliceCost * w;
                weightSum += w;

                if (textComp >= meanTextComp || energy >= meanEnergy)
                {
                    textDiffSum += totalSliceCost;
                    textSliceCount++;
                }
            }

            double meanWeightedDiff = weightedDiffSum / Math.Max(1.0, weightSum);

            if (textSliceCount >= 3)
            {
                double textMeanDiff = textDiffSum / textSliceCount;
                meanWeightedDiff = meanWeightedDiff * 0.30 + textMeanDiff * 0.70;
            }

            if (band0WeightSum >= 12.0 && band1WeightSum >= 12.0)
            {
                double b0Err = band0WeightedSum / band0WeightSum;
                double b1Err = band1WeightedSum / band1WeightSum;
                meanWeightedDiff = meanWeightedDiff * 0.45 + Math.Max(b0Err, b1Err) * 0.55;
            }

            // Prevent blank white gaps from winning with 0 error when they contain almost no aligned features
            if (bothFeatureSlices < 3)
            {
                meanWeightedDiff += (3 - bothFeatureSlices) * 6.0;
            }

            double hashRatio = (double)exactHashMatches / overlapLen;
            return meanWeightedDiff - (hashRatio * 1.6) + (delta * 0.002);
        }

        private static void SortTopK(int[] deltas, double[] costs)
        {
            for (int i = 1; i < costs.Length; i++)
            {
                double c = costs[i];
                int d = deltas[i];
                int j = i - 1;
                while (j >= 0 && costs[j] > c)
                {
                    costs[j + 1] = costs[j];
                    deltas[j + 1] = deltas[j];
                    j--;
                }
                costs[j + 1] = c;
                deltas[j + 1] = d;
            }
        }

        private unsafe double VerifyCandidate2DPixels(
            NormalizedFrame prevNorm, NormalizedFrame currNorm,
            Bitmap prevBmp, Bitmap currBmp,
            int activeStart, int activeEnd, int delta, int meanEnergy, int meanTextComp, bool[] crossMask, int midBin)
        {
            int overlapStartInPrev = activeStart + delta;
            int overlapLen = activeEnd - overlapStartInPrev;
            if (overlapLen < 20) return 255.0;

            Rectangle rect = new Rectangle(0, 0, prevBmp.Width, prevBmp.Height);
            BitmapData dataPrev = prevBmp.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            BitmapData dataCurr = currBmp.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);

            try
            {
                byte* ptrPrev = (byte*)dataPrev.Scan0;
                byte* ptrCurr = (byte*)dataCurr.Scan0;
                int stridePrev = dataPrev.Stride;
                int strideCurr = dataCurr.Stride;

                int crossStart = Math.Min(LEADING_BORDER_MARGIN, _crossDimension / 8);
                int crossEnd = Math.Max(crossStart + 8, _crossDimension - Math.Min(SCROLLBAR_MARGIN, _crossDimension / 5));
                int activeCrossSpan = Math.Max(1, crossEnd - crossStart);

                double totalWeightedErr = 0.0;
                double totalWeight = 0.0;
                double band0WeightedErr = 0.0;
                double band0Weight = 0.0;
                double band1WeightedErr = 0.0;
                double band1Weight = 0.0;
                int importantSlicesEvaluated = 0;
                int severeMismatchSlices = 0;
                int matchedTextSlices = 0;
                bool allowSubpixel = delta >= 0;

                for (int sPrev = overlapStartInPrev; sPrev < activeEnd; sPrev++)
                {
                    int sCurr = sPrev - delta;
                    int textComp = Math.Max(prevNorm.TextComplexity[sPrev], currNorm.TextComplexity[sCurr]);
                    int energy = Math.Max(prevNorm.EdgeEnergy[sPrev], currNorm.EdgeEnergy[sCurr]);

                    bool isImportantSlice = (textComp >= meanTextComp) || (energy >= meanEnergy);
                    if (!isImportantSlice && ((sPrev - overlapStartInPrev) & 3) != 0)
                    {
                        continue;
                    }
                    if (isImportantSlice) importantSlicesEvaluated++;

                    double rowWeight = (textComp >= meanTextComp) ? 10.0 : (energy >= meanEnergy ? 4.0 : 0.5);

                    long sliceDiff = 0;
                    long sampleWeight = 0;
                    long band0Diff = 0;
                    long band0SampW = 0;
                    int band0Edges = 0;
                    long band1Diff = 0;
                    long band1SampW = 0;
                    int band1Edges = 0;

                    if (_direction == ScrollDirection.Vertical)
                    {
                        byte* rowPrev = ptrPrev + sPrev * stridePrev;
                        byte* rowPrevM1 = (allowSubpixel && sPrev > 0) ? (ptrPrev + (sPrev - 1) * stridePrev) : rowPrev;
                        byte* rowPrevP1 = (allowSubpixel && sPrev + 1 < prevNorm.PrimaryLen) ? (ptrPrev + (sPrev + 1) * stridePrev) : rowPrev;
                        byte* rowCurr = ptrCurr + sCurr * strideCurr;
                        byte* rowCurrM1 = (allowSubpixel && sCurr > 0) ? (ptrCurr + (sCurr - 1) * strideCurr) : rowCurr;
                        byte* rowCurrP1 = (allowSubpixel && sCurr + 1 < prevNorm.PrimaryLen) ? (ptrCurr + (sCurr + 1) * strideCurr) : rowCurr;
                        byte* rowPrevUp = (sPrev >= 2) ? (ptrPrev + (sPrev - 2) * stridePrev) : rowPrev;
                        byte* rowCurrUp = (sCurr >= 2) ? (ptrCurr + (sCurr - 2) * strideCurr) : rowCurr;

                        for (int x = crossStart; x < crossEnd; x += 2)
                        {
                            int bin = ((x - crossStart) * SAMPLE_COUNT) / activeCrossSpan;
                            if (crossMask != null)
                            {
                                if (bin >= 0 && bin < SAMPLE_COUNT && !crossMask[bin]) continue;
                            }

                            int idx = x * 4;
                            int lumaPrev = rowPrev[idx + 1];
                            int lumaCurr = rowCurr[idx + 1];
                            int deadband = (lumaPrev > 236 && lumaCurr > 236) ? 10 : 2;

                            int db = Math.Max(0, Math.Abs(rowPrev[idx] - rowCurr[idx]) - deadband);
                            int dg = Math.Max(0, Math.Abs(lumaPrev - lumaCurr) - deadband);
                            int dr = Math.Max(0, Math.Abs(rowPrev[idx + 2] - rowCurr[idx + 2]) - deadband);

                            int lumaPrevUp = rowPrevUp[idx + 1];
                            int lumaCurrUp = rowCurrUp[idx + 1];
                            int gradPrev = lumaPrev - lumaPrevUp;
                            int gradCurr = lumaCurr - lumaCurrUp;
                            int gradErr = Math.Abs(gradPrev - gradCurr);

                            int pixErr = db + dg + dr + gradErr;
                            if (allowSubpixel && pixErr > 8)
                            {
                                bool hasPrevEdge = Math.Abs(gradPrev) > 4 || Math.Abs(lumaPrev - rowPrevM1[idx + 1]) > 4 || Math.Abs(lumaPrev - rowPrevP1[idx + 1]) > 4;
                                bool hasCurrEdge = Math.Abs(gradCurr) > 4 || Math.Abs(lumaCurr - rowCurrM1[idx + 1]) > 4 || Math.Abs(lumaCurr - rowCurrP1[idx + 1]) > 4;
                                if (hasPrevEdge && hasCurrEdge)
                                {
                                    // 1. Sharp prev vs blurred curr (half-step in curr)
                                    int bCM = (rowCurr[idx] + rowCurrM1[idx]) >> 1;
                                    int gCM = (lumaCurr + rowCurrM1[idx + 1]) >> 1;
                                    int rCM = (rowCurr[idx + 2] + rowCurrM1[idx + 2]) >> 1;
                                    int gradErrCM = Math.Min(gradErr, Math.Abs(gradPrev - (gCM - lumaCurrUp))) >> 1;
                                    int errCM = Math.Max(0, Math.Abs(rowPrev[idx] - bCM) - deadband)
                                              + Math.Max(0, Math.Abs(lumaPrev - gCM) - deadband)
                                              + Math.Max(0, Math.Abs(rowPrev[idx + 2] - rCM) - deadband)
                                              + gradErrCM + 2;
                                    if (errCM < pixErr) pixErr = errCM;

                                    int bCP = (rowCurr[idx] + rowCurrP1[idx]) >> 1;
                                    int gCP = (lumaCurr + rowCurrP1[idx + 1]) >> 1;
                                    int rCP = (rowCurr[idx + 2] + rowCurrP1[idx + 2]) >> 1;
                                    int gradErrCP = Math.Min(Math.Abs(gradPrev - (gCP - lumaCurrUp)), Math.Abs(gradPrev - (gCP - rowCurrM1[idx + 1]))) >> 1;
                                    int errCP = Math.Max(0, Math.Abs(rowPrev[idx] - bCP) - deadband)
                                              + Math.Max(0, Math.Abs(lumaPrev - gCP) - deadband)
                                              + Math.Max(0, Math.Abs(rowPrev[idx + 2] - rCP) - deadband)
                                              + gradErrCP + 2;
                                    if (errCP < pixErr) pixErr = errCP;

                                    // 2. Blurred prev (half-step in prev) vs sharp curr
                                    int bPM = (rowPrev[idx] + rowPrevM1[idx]) >> 1;
                                    int gPM = (lumaPrev + rowPrevM1[idx + 1]) >> 1;
                                    int rPM = (rowPrev[idx + 2] + rowPrevM1[idx + 2]) >> 1;
                                    int gradErrPM = Math.Min(gradErr, Math.Abs((gPM - lumaPrevUp) - gradCurr)) >> 1;
                                    int errPM = Math.Max(0, Math.Abs(bPM - rowCurr[idx]) - deadband)
                                              + Math.Max(0, Math.Abs(gPM - lumaCurr) - deadband)
                                              + Math.Max(0, Math.Abs(rPM - rowCurr[idx + 2]) - deadband)
                                              + gradErrPM + 2;
                                    if (errPM < pixErr) pixErr = errPM;

                                    int bPP = (rowPrev[idx] + rowPrevP1[idx]) >> 1;
                                    int gPP = (lumaPrev + rowPrevP1[idx + 1]) >> 1;
                                    int rPP = (rowPrev[idx + 2] + rowPrevP1[idx + 2]) >> 1;
                                    int gradErrPP = Math.Min(Math.Abs((gPP - lumaPrevUp) - gradCurr), Math.Abs((gPP - rowPrevM1[idx + 1]) - gradCurr)) >> 1;
                                    int errPP = Math.Max(0, Math.Abs(bPP - rowCurr[idx]) - deadband)
                                              + Math.Max(0, Math.Abs(gPP - lumaCurr) - deadband)
                                              + Math.Max(0, Math.Abs(rPP - rowCurr[idx + 2]) - deadband)
                                              + gradErrPP + 2;
                                    if (errPP < pixErr) pixErr = errPP;
                                }
                            }

                            bool isScrollEdge = (Math.Abs(gradPrev) > 5 || Math.Abs(gradCurr) > 5);
                            int w = isScrollEdge ? 10 : 1;

                            sliceDiff += pixErr * w;
                            sampleWeight += 3 * w;
                            if (bin <= midBin)
                            {
                                band0Diff += pixErr * w;
                                band0SampW += 3 * w;
                                if (isScrollEdge) band0Edges++;
                            }
                            else
                            {
                                band1Diff += pixErr * w;
                                band1SampW += 3 * w;
                                if (isScrollEdge) band1Edges++;
                            }
                        }
                    }
                    else
                    {
                        int xPrevOffset = sPrev * 4;
                        int xPrevM1Offset = (allowSubpixel && sPrev > 0) ? ((sPrev - 1) * 4) : xPrevOffset;
                        int xPrevP1Offset = (allowSubpixel && sPrev + 1 < prevNorm.PrimaryLen) ? ((sPrev + 1) * 4) : xPrevOffset;
                        int xCurrOffset = sCurr * 4;
                        int xCurrM1Offset = (allowSubpixel && sCurr > 0) ? ((sCurr - 1) * 4) : xCurrOffset;
                        int xCurrP1Offset = (allowSubpixel && sCurr + 1 < prevNorm.PrimaryLen) ? ((sCurr + 1) * 4) : xCurrOffset;
                        int xPrevLeftOffset = (sPrev >= 2) ? ((sPrev - 2) * 4) : xPrevOffset;
                        int xCurrLeftOffset = (sCurr >= 2) ? ((sCurr - 2) * 4) : xCurrOffset;

                        for (int y = crossStart; y < crossEnd; y += 2)
                        {
                            int bin = ((y - crossStart) * SAMPLE_COUNT) / activeCrossSpan;
                            if (crossMask != null)
                            {
                                if (bin >= 0 && bin < SAMPLE_COUNT && !crossMask[bin]) continue;
                            }

                            byte* rowPtrPrev = ptrPrev + y * stridePrev;
                            byte* rowPtrCurr = ptrCurr + y * strideCurr;
                            byte* pxPrev = rowPtrPrev + xPrevOffset;
                            byte* pxCurr = rowPtrCurr + xCurrOffset;

                            int lumaPrev = pxPrev[1];
                            int lumaCurr = pxCurr[1];
                            int deadband = (lumaPrev > 236 && lumaCurr > 236) ? 10 : 2;

                            int db = Math.Max(0, Math.Abs(pxPrev[0] - pxCurr[0]) - deadband);
                            int dg = Math.Max(0, Math.Abs(lumaPrev - lumaCurr) - deadband);
                            int dr = Math.Max(0, Math.Abs(pxPrev[2] - pxCurr[2]) - deadband);

                            int lumaPrevLeft = (rowPtrPrev + xPrevLeftOffset)[1];
                            int lumaCurrLeft = (rowPtrCurr + xCurrLeftOffset)[1];
                            int gradPrev = lumaPrev - lumaPrevLeft;
                            int gradCurr = lumaCurr - lumaCurrLeft;
                            int gradErr = Math.Abs(gradPrev - gradCurr);

                            int pixErr = db + dg + dr + gradErr;
                            if (allowSubpixel && pixErr > 8)
                            {
                                byte* pxCM1 = rowPtrCurr + xCurrM1Offset;
                                byte* pxCP1 = rowPtrCurr + xCurrP1Offset;
                                byte* pxPM1 = rowPtrPrev + xPrevM1Offset;
                                byte* pxPP1 = rowPtrPrev + xPrevP1Offset;

                                bool hasPrevEdge = Math.Abs(gradPrev) > 4 || Math.Abs(lumaPrev - pxPM1[1]) > 4 || Math.Abs(lumaPrev - pxPP1[1]) > 4;
                                bool hasCurrEdge = Math.Abs(gradCurr) > 4 || Math.Abs(lumaCurr - pxCM1[1]) > 4 || Math.Abs(lumaCurr - pxCP1[1]) > 4;
                                if (hasPrevEdge && hasCurrEdge)
                                {
                                    // 1. Sharp prev vs blurred curr (half-step in curr)
                                    int bCM = (pxCurr[0] + pxCM1[0]) >> 1;
                                    int gCM = (lumaCurr + pxCM1[1]) >> 1;
                                    int rCM = (pxCurr[2] + pxCM1[2]) >> 1;
                                    int gradErrCM = Math.Min(gradErr, Math.Abs(gradPrev - (gCM - lumaCurrLeft))) >> 1;
                                    int errCM = Math.Max(0, Math.Abs(pxPrev[0] - bCM) - deadband)
                                              + Math.Max(0, Math.Abs(lumaPrev - gCM) - deadband)
                                              + Math.Max(0, Math.Abs(pxPrev[2] - rCM) - deadband)
                                              + gradErrCM + 2;
                                    if (errCM < pixErr) pixErr = errCM;

                                    int bCP = (pxCurr[0] + pxCP1[0]) >> 1;
                                    int gCP = (lumaCurr + pxCP1[1]) >> 1;
                                    int rCP = (pxCurr[2] + pxCP1[2]) >> 1;
                                    int gradErrCP = Math.Min(Math.Abs(gradPrev - (gCP - lumaCurrLeft)), Math.Abs(gradPrev - (gCP - pxCM1[1]))) >> 1;
                                    int errCP = Math.Max(0, Math.Abs(pxPrev[0] - bCP) - deadband)
                                              + Math.Max(0, Math.Abs(lumaPrev - gCP) - deadband)
                                              + Math.Max(0, Math.Abs(pxPrev[2] - rCP) - deadband)
                                              + gradErrCP + 2;
                                    if (errCP < pixErr) pixErr = errCP;

                                    // 2. Blurred prev (half-step in prev) vs sharp curr
                                    int bPM = (pxPrev[0] + pxPM1[0]) >> 1;
                                    int gPM = (lumaPrev + pxPM1[1]) >> 1;
                                    int rPM = (pxPrev[2] + pxPM1[2]) >> 1;
                                    int gradErrPM = Math.Min(gradErr, Math.Abs((gPM - lumaPrevLeft) - gradCurr)) >> 1;
                                    int errPM = Math.Max(0, Math.Abs(bPM - pxCurr[0]) - deadband)
                                              + Math.Max(0, Math.Abs(gPM - lumaCurr) - deadband)
                                              + Math.Max(0, Math.Abs(rPM - pxCurr[2]) - deadband)
                                              + gradErrPM + 2;
                                    if (errPM < pixErr) pixErr = errPM;

                                    int bPP = (pxPrev[0] + pxPP1[0]) >> 1;
                                    int gPP = (lumaPrev + pxPP1[1]) >> 1;
                                    int rPP = (pxPrev[2] + pxPP1[2]) >> 1;
                                    int gradErrPP = Math.Min(Math.Abs((gPP - lumaPrevLeft) - gradCurr), Math.Abs((gPP - pxPM1[1]) - gradCurr)) >> 1;
                                    int errPP = Math.Max(0, Math.Abs(bPP - pxCurr[0]) - deadband)
                                              + Math.Max(0, Math.Abs(gPP - lumaCurr) - deadband)
                                              + Math.Max(0, Math.Abs(rPP - pxCurr[2]) - deadband)
                                              + gradErrPP + 2;
                                    if (errPP < pixErr) pixErr = errPP;
                                }
                            }

                            bool isScrollEdge = (Math.Abs(gradPrev) > 5 || Math.Abs(gradCurr) > 5);
                            int w = isScrollEdge ? 10 : 1;

                            sliceDiff += pixErr * w;
                            sampleWeight += 3 * w;
                            if (bin <= midBin)
                            {
                                band0Diff += pixErr * w;
                                band0SampW += 3 * w;
                                if (isScrollEdge) band0Edges++;
                            }
                            else
                            {
                                band1Diff += pixErr * w;
                                band1SampW += 3 * w;
                                if (isScrollEdge) band1Edges++;
                            }
                        }
                    }

                    double avgSliceErr = sampleWeight > 0 ? (double)sliceDiff / sampleWeight : 0.0;
                    if (sampleWeight > 0)
                    {
                        totalWeightedErr += avgSliceErr * rowWeight;
                        totalWeight += rowWeight;
                    }
                    double b0SliceAvg = (band0SampW > 0 && band0Edges > 0) ? (double)band0Diff / band0SampW : 0.0;
                    if (band0SampW > 0 && band0Edges > 0)
                    {
                        double b0SliceW = 1.0 + band0Edges * 2.5;
                        band0WeightedErr += b0SliceAvg * b0SliceW;
                        band0Weight += b0SliceW;
                    }
                    double b1SliceAvg = (band1SampW > 0 && band1Edges > 0) ? (double)band1Diff / band1SampW : 0.0;
                    if (band1SampW > 0 && band1Edges > 0)
                    {
                        double b1SliceW = 1.0 + band1Edges * 2.5;
                        band1WeightedErr += b1SliceAvg * b1SliceW;
                        band1Weight += b1SliceW;
                    }

                    if (isImportantSlice && (avgSliceErr > 16.0 || (band0Edges >= 2 && b0SliceAvg > 18.0) || (band1Edges >= 2 && b1SliceAvg > 18.0)))
                    {
                        severeMismatchSlices++;
                    }
                    if (prevNorm.TextComplexity[sPrev] >= meanTextComp / 2 && currNorm.TextComplexity[sCurr] >= meanTextComp / 2 && avgSliceErr < 14.0)
                    {
                        matchedTextSlices++;
                    }
                }

                double finalErr = totalWeight > 0 ? (totalWeightedErr / totalWeight) : 255.0;
                if (band0Weight >= 10.0 && band1Weight >= 10.0)
                {
                    double b0Err = band0WeightedErr / band0Weight;
                    double b1Err = band1WeightedErr / band1Weight;
                    finalErr = finalErr * 0.45 + Math.Max(b0Err, b1Err) * 0.55;
                }
                if (severeMismatchSlices >= 4 && importantSlicesEvaluated > 0)
                {
                    finalErr += ((double)severeMismatchSlices / importantSlicesEvaluated) * 18.0;
                }
                if (importantSlicesEvaluated < 3 && delta >= 5)
                {
                    finalErr += (3 - importantSlicesEvaluated) * 5.0;
                }
                if (delta >= 5 && matchedTextSlices < 3 && importantSlicesEvaluated < 6)
                {
                    finalErr += (3 - matchedTextSlices) * 4.0;
                }
                return finalErr;
            }
            finally
            {
                prevBmp.UnlockBits(dataPrev);
                currBmp.UnlockBits(dataCurr);
            }
        }

        private static double SliceBandDifference(
            NormalizedFrame a, int sa, NormalizedFrame b, int sb,
            bool[] crossMask, int midBin,
            out double band0SliceErr, out int band0EdgeCount,
            out double band1SliceErr, out int band1EdgeCount)
        {
            byte[] lumaA = a.LumaSamples[sa];
            byte[] lumaAM1 = (sa > 0 && sa != sb) ? a.LumaSamples[sa - 1] : lumaA;
            byte[] lumaAP1 = (sa + 1 < a.PrimaryLen && sa != sb) ? a.LumaSamples[sa + 1] : lumaA;
            byte[] lumaB = b.LumaSamples[sb];
            byte[] lumaBM1 = (sb > 0 && sa != sb) ? b.LumaSamples[sb - 1] : lumaB;
            byte[] lumaBP1 = (sb + 1 < b.PrimaryLen && sa != sb) ? b.LumaSamples[sb + 1] : lumaB;
            byte[] peakA = a.PeakContrast[sa];
            byte[] peakB = b.PeakContrast[sb];
            byte[] gradA = a.ScrollGrad[sa];
            byte[] gradAM1 = (sa > 0 && sa != sb) ? a.ScrollGrad[sa - 1] : gradA;
            byte[] gradAP1 = (sa + 1 < a.PrimaryLen && sa != sb) ? a.ScrollGrad[sa + 1] : gradA;
            byte[] gradB = b.ScrollGrad[sb];
            byte[] gradBM1 = (sb > 0 && sa != sb) ? b.ScrollGrad[sb - 1] : gradB;
            byte[] gradBP1 = (sb + 1 < b.PrimaryLen && sa != sb) ? b.ScrollGrad[sb + 1] : gradB;
            short[] chromaA = a.ChromaSamples[sa];
            short[] chromaB = b.ChromaSamples[sb];

            int diff = 0;
            int weightSum = 0;
            int b0Diff = 0;
            int b0W = 0;
            int b1Diff = 0;
            int b1W = 0;
            band0EdgeCount = 0;
            band1EdgeCount = 0;

            for (int i = 0; i < SAMPLE_COUNT; i++)
            {
                if (crossMask != null && !crossMask[i]) continue;
                int rawDl = Math.Abs(lumaA[i] - lumaB[i]);
                int dl = (lumaA[i] > 236 && lumaB[i] > 236) ? Math.Max(0, rawDl - 10) : Math.Max(0, rawDl - 2);
                int dp = Math.Max(0, Math.Abs(peakA[i] - peakB[i]) - 6);
                int dg = Math.Abs(gradA[i] - gradB[i]);
                int dc = Math.Max(0, (Math.Abs(chromaA[i] - chromaB[i]) >> 1) - 6);

                int binCost = dl + dp + dg + dc;
                if (sa != sb && binCost > 8)
                {
                    bool hasEdgeA = gradA[i] >= 4 || gradAM1[i] >= 4 || gradAP1[i] >= 4 || peakA[i] >= 10;
                    bool hasEdgeB = gradB[i] >= 4 || gradBM1[i] >= 4 || gradBP1[i] >= 4 || peakB[i] >= 10;
                    if (hasEdgeA && hasEdgeB)
                    {
                        int dpHalf = dp >> 1;

                        int lBM = (lumaB[i] + lumaBM1[i]) >> 1;
                        int gBM = (gradB[i] + gradBM1[i]) >> 1;
                        int costBM = Math.Max(0, Math.Abs(lumaA[i] - lBM) - 3) + dpHalf + (Math.Abs(gradA[i] - gBM) >> 1) + dc + 2;
                        if (costBM < binCost) binCost = costBM;

                        int lBP = (lumaB[i] + lumaBP1[i]) >> 1;
                        int gBP = (gradB[i] + gradBP1[i]) >> 1;
                        int costBP = Math.Max(0, Math.Abs(lumaA[i] - lBP) - 3) + dpHalf + (Math.Abs(gradA[i] - gBP) >> 1) + dc + 2;
                        if (costBP < binCost) binCost = costBP;

                        int lAM = (lumaA[i] + lumaAM1[i]) >> 1;
                        int gAM = (gradA[i] + gradAM1[i]) >> 1;
                        int costAM = Math.Max(0, Math.Abs(lAM - lumaB[i]) - 3) + dpHalf + (Math.Abs(gAM - gradB[i]) >> 1) + dc + 2;
                        if (costAM < binCost) binCost = costAM;

                        int lAP = (lumaA[i] + lumaAP1[i]) >> 1;
                        int gAP = (gradA[i] + gradAP1[i]) >> 1;
                        int costAP = Math.Max(0, Math.Abs(lAP - lumaB[i]) - 3) + dpHalf + (Math.Abs(gAP - gradB[i]) >> 1) + dc + 2;
                        if (costAP < binCost) binCost = costAP;
                    }
                }

                bool isScrollEdge = (gradA[i] >= 6 || gradB[i] >= 6);
                int w = isScrollEdge ? 6 : 1;
                diff += binCost * w;
                weightSum += w;

                if (i <= midBin)
                {
                    b0Diff += binCost * w;
                    b0W += w;
                    if (isScrollEdge) band0EdgeCount++;
                }
                else
                {
                    b1Diff += binCost * w;
                    b1W += w;
                    if (isScrollEdge) band1EdgeCount++;
                }
            }

            band0SliceErr = b0W > 0 ? (double)b0Diff / b0W : 0.0;
            band1SliceErr = b1W > 0 ? (double)b1Diff / b1W : 0.0;
            return weightSum > 0 ? (double)diff / weightSum : 0.0;
        }

        private static double SliceDifference(NormalizedFrame a, int sa, NormalizedFrame b, int sb, bool[] crossMask)
        {
            double b0e, b1e;
            int b0c, b1c;
            return SliceBandDifference(a, sa, b, sb, crossMask, SAMPLE_COUNT / 2, out b0e, out b0c, out b1e, out b1c);
        }

        private static unsafe NormalizedFrame ExtractNormalizedFrame(Bitmap bmp, ScrollDirection direction)
        {
            int width = bmp.Width;
            int height = bmp.Height;

            int primaryLen = direction == ScrollDirection.Vertical ? height : width;
            int crossLen = direction == ScrollDirection.Vertical ? width : height;

            NormalizedFrame norm = new NormalizedFrame
            {
                PrimaryLen = primaryLen,
                CrossLen = crossLen,
                LumaSamples = new byte[primaryLen][],
                PeakContrast = new byte[primaryLen][],
                ScrollGrad = new byte[primaryLen][],
                ChromaSamples = new short[primaryLen][],
                EdgeEnergy = new int[primaryLen],
                TextComplexity = new int[primaryLen],
                RowHash = new ulong[primaryLen]
            };

            int crossStart = Math.Min(LEADING_BORDER_MARGIN, crossLen / 8);
            int crossEnd = Math.Max(crossStart + 4, crossLen - Math.Min(SCROLLBAR_MARGIN, crossLen / 5));
            int activeCrossSpan = Math.Max(1, crossEnd - crossStart);

            Rectangle rect = new Rectangle(0, 0, width, height);
            BitmapData data = bmp.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            try
            {
                byte* scan0 = (byte*)data.Scan0;
                int stride = data.Stride;

                for (int p = 0; p < primaryLen; p++)
                {
                    byte[] luma = new byte[SAMPLE_COUNT];
                    byte[] peak = new byte[SAMPLE_COUNT];
                    byte[] sgrad = new byte[SAMPLE_COUNT];
                    short[] chroma = new short[SAMPLE_COUNT];

                    int scrollAxisEnergySum = 0;
                    int textComplexitySum = 0;
                    ulong hash = 14695981039346656037UL;

                    for (int k = 0; k < SAMPLE_COUNT; k++)
                    {
                        int c0 = crossStart + (k * activeCrossSpan) / SAMPLE_COUNT;
                        int c1 = crossStart + ((k + 1) * activeCrossSpan) / SAMPLE_COUNT;
                        if (c1 <= c0) c1 = c0 + 1;

                        int step = (c1 - c0) > 8 ? 2 : 1;
                        int sumY = 0;
                        int sumC = 0;
                        int minY = 255;
                        int maxY = 0;
                        int count = 0;

                        for (int c = c0; c < c1; c += step)
                        {
                            byte* px = (direction == ScrollDirection.Vertical)
                                ? (scan0 + p * stride + c * 4)
                                : (scan0 + c * stride + p * 4);

                            int b = px[0];
                            int g = px[1];
                            int r = px[2];

                            int yVal = (r * 77 + g * 150 + b * 29) >> 8;
                            int cVal = (r - b) + (g - b);

                            sumY += yVal;
                            sumC += cVal;
                            if (yVal < minY) minY = yVal;
                            if (yVal > maxY) maxY = yVal;
                            count++;
                        }

                        int meanY = sumY / count;
                        byte effectiveLuma = (byte)((meanY * 2 + minY) / 3);
                        byte contrastY = (byte)(maxY - minY);
                        short avgC = (short)(sumC / count);

                        luma[k] = effectiveLuma;
                        peak[k] = contrastY;
                        chroma[k] = avgC;

                        byte gradP = 0;
                        if (p > 0)
                        {
                            int dl = Math.Abs(effectiveLuma - norm.LumaSamples[p - 1][k]);
                            int dp = Math.Abs(contrastY - norm.PeakContrast[p - 1][k]);
                            gradP = (byte)Math.Min(255, dl + (dp >> 1));
                            scrollAxisEnergySum += gradP;
                        }
                        sgrad[k] = gradP;

                        if (k > 0)
                        {
                            int gradVar = Math.Abs(gradP - sgrad[k - 1]);
                            if (gradP > 5)
                            {
                                textComplexitySum += gradP + gradVar;
                            }
                        }

                        ulong quantized = (ulong)((effectiveLuma >> 2) ^ (contrastY >> 2) ^ (gradP >> 2));
                        hash ^= quantized;
                        hash *= 1099511628211UL;
                    }

                    norm.LumaSamples[p] = luma;
                    norm.PeakContrast[p] = peak;
                    norm.ScrollGrad[p] = sgrad;
                    norm.ChromaSamples[p] = chroma;
                    norm.EdgeEnergy[p] = scrollAxisEnergySum / 8;
                    norm.TextComplexity[p] = textComplexitySum / 8;
                    norm.RowHash[p] = hash;
                }
            }
            finally
            {
                bmp.UnlockBits(data);
            }

            return norm;
        }

        public void Dispose()
        {
            ClearUndoStack();
            ClearLastUnmatched();
            if (_prevBitmap != null)
            {
                _prevBitmap.Dispose();
                _prevBitmap = null;
            }
            for (int i = 0; i < _strips.Count; i++)
            {
                if (_strips[i].Bitmap != null)
                {
                    _strips[i].Bitmap.Dispose();
                }
            }
            _strips.Clear();
        }
    }
}
