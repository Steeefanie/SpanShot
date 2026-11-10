import Foundation

public enum ScrollDirection: Int {
    case vertical = 0   // Top-to-Bottom scrolling (content moves up)
    case horizontal = 1 // Left-to-Right scrolling (content moves left)
}

public enum StitchStatus {
    case firstFrame
    case noMovement
    case stitched
    case scrolledBackward
    case lowConfidence
    case maxLengthReached
}

public struct StitchResult {
    public var status: StitchStatus
    public var deltaPixels: Int
    public var confidence: Double
    public var totalLength: Int
    public var frameCount: Int
    public var detectedStickyHead: Int
    public var detectedStickyTail: Int

    public init(
        status: StitchStatus,
        deltaPixels: Int = 0,
        confidence: Double = 0.0,
        totalLength: Int = 0,
        frameCount: Int = 0,
        detectedStickyHead: Int = 0,
        detectedStickyTail: Int = 0
    ) {
        self.status = status
        self.deltaPixels = deltaPixels
        self.confidence = confidence
        self.totalLength = totalLength
        self.frameCount = frameCount
        self.detectedStickyHead = detectedStickyHead
        self.detectedStickyTail = detectedStickyTail
    }
}

/// High-precision 1D+2D hybrid image stitching engine for both Vertical and Horizontal scrolling captures.
/// 1:1 port of src/StitchEngine.cs.
public final class StitchEngine {
    private static let SAMPLE_COUNT = 64
    private static let SCROLLBAR_MARGIN = 18
    private static let LEADING_BORDER_MARGIN = 6
    private static let MAX_CANVAS_LENGTH = 60000

    private let _direction: ScrollDirection
    private var _prevFrame: NormalizedFrame?
    private var _prevBitmap: RawBitmap?

    private var _strips: [CanvasStrip] = []
    private var _undoStack: [HistorySnapshot] = []

    private var _crossDimension: Int = 0
    private var _primaryFrameDimension: Int = 0
    private var _globalOffset: Int = 0
    private var _totalCanvasLength: Int = 0
    private var _frameCount: Int = 0
    private var _runningStickyHead: Int = 0
    private var _runningStickyTail: Int = 0
    private var _runningCrossMask: [Bool]?
    private var _consecutiveLowConfidence: Int = 0
    private var _lastUnmatchedFrame: NormalizedFrame?
    private var _lastUnmatchedBitmap: RawBitmap?

    private struct CanvasStrip {
        var globalStart: Int
        var length: Int
        var bitmap: RawBitmap
        var srcOffset: Int
    }

    private struct HistorySnapshot {
        var stripCountBefore: Int
        var lastStripLengthBefore: Int
        var globalOffsetBefore: Int
        var totalCanvasLengthBefore: Int
        var frameCountBefore: Int
        var prevBitmapClone: RawBitmap
    }

    internal final class NormalizedFrame {
        let primaryLen: Int
        let crossLen: Int
        var lumaSamples: [[UInt8]]      // [PrimaryLen][SAMPLE_COUNT] box-averaged luma
        var peakContrast: [[UInt8]]     // [PrimaryLen][SAMPLE_COUNT] max-min contrast inside bin
        var scrollGrad: [[UInt8]]       // [PrimaryLen][SAMPLE_COUNT] |Luma[p][k] - Luma[p-1][k]| along scroll axis
        var chromaSamples: [[Int16]]    // [PrimaryLen][SAMPLE_COUNT] color signature
        var edgeEnergy: [Int]           // [PrimaryLen] scroll-axis edge energy (ignores parallel grid lines)
        var textComplexity: [Int]       // [PrimaryLen] high for text/characters, low for uniform grid lines or whitespace
        var rowHash: [UInt64]           // [PrimaryLen] 64-bit perceptual hash

        init(primaryLen: Int, crossLen: Int) {
            self.primaryLen = primaryLen
            self.crossLen = crossLen
            self.lumaSamples = Array(repeating: [], count: primaryLen)
            self.peakContrast = Array(repeating: [], count: primaryLen)
            self.scrollGrad = Array(repeating: [], count: primaryLen)
            self.chromaSamples = Array(repeating: [], count: primaryLen)
            self.edgeEnergy = Array(repeating: 0, count: primaryLen)
            self.textComplexity = Array(repeating: 0, count: primaryLen)
            self.rowHash = Array(repeating: 0, count: primaryLen)
        }
    }

    public var direction: ScrollDirection { _direction }
    public var totalCanvasLength: Int { _totalCanvasLength }
    public var crossDimension: Int { _crossDimension }
    public var frameCount: Int { _frameCount }
    public var canUndo: Bool { !_undoStack.isEmpty }

    public init(direction: ScrollDirection) {
        self._direction = direction
    }

    public func reset() {
        _undoStack.removeAll()
        _prevBitmap = nil
        _prevFrame = nil
        _strips.removeAll()
        _globalOffset = 0
        _totalCanvasLength = 0
        _frameCount = 0
        _runningStickyHead = 0
        _runningStickyTail = 0
        _runningCrossMask = nil
        _consecutiveLowConfidence = 0
        clearLastUnmatched()
    }

    private func clearLastUnmatched() {
        _lastUnmatchedFrame = nil
        _lastUnmatchedBitmap = nil
    }

    @discardableResult
    public func undoLastFrame() -> Bool {
        guard let snap = _undoStack.popLast() else { return false }
        clearLastUnmatched()

        while _strips.count > snap.stripCountBefore {
            _strips.removeLast()
        }

        if !_strips.isEmpty {
            _strips[_strips.count - 1].length = snap.lastStripLengthBefore
        }

        _globalOffset = snap.globalOffsetBefore
        _totalCanvasLength = snap.totalCanvasLengthBefore
        _frameCount = snap.frameCountBefore

        _prevBitmap = snap.prevBitmapClone
        _prevFrame = Self.ExtractNormalizedFrame(bmp: snap.prevBitmapClone, direction: _direction)
        return true
    }

    public func pushFrame(_ frame: RawBitmap) -> StitchResult {
        let norm = Self.ExtractNormalizedFrame(bmp: frame, direction: _direction)

        guard let prevFrame = _prevFrame, let prevBitmap = _prevBitmap else {
            _prevFrame = norm
            _prevBitmap = frame.clone()
            _primaryFrameDimension = norm.primaryLen
            _crossDimension = norm.crossLen
            _globalOffset = 0
            _totalCanvasLength = norm.primaryLen
            _frameCount = 1

            _strips.append(CanvasStrip(
                globalStart: 0,
                length: norm.primaryLen,
                bitmap: frame.clone(),
                srcOffset: 0
            ))

            return StitchResult(
                status: .firstFrame,
                deltaPixels: 0,
                confidence: 1.0,
                totalLength: _totalCanvasLength,
                frameCount: _frameCount
            )
        }

        if norm.primaryLen != _primaryFrameDimension || norm.crossLen != _crossDimension {
            return StitchResult(
                status: .lowConfidence,
                deltaPixels: 0,
                confidence: 0.0,
                totalLength: _totalCanvasLength,
                frameCount: _frameCount
            )
        }

        if _totalCanvasLength >= Self.MAX_CANVAS_LENGTH {
            return StitchResult(
                status: .maxLengthReached,
                deltaPixels: 0,
                confidence: 1.0,
                totalLength: _totalCanvasLength,
                frameCount: _frameCount
            )
        }

        // 1. Check whether any sub-region of the frame has moved (supports tables where 50%+ is frozen/static)
        var zeroDiff: Double = 0.0
        if !Self.HasFrameMoved(prev: prevFrame, curr: norm, zeroDiff: &zeroDiff) {
            return StitchResult(
                status: .noMovement,
                deltaPixels: 0,
                confidence: 1.0 - (zeroDiff / 255.0),
                totalLength: _totalCanvasLength,
                frameCount: _frameCount,
                detectedStickyHead: _runningStickyHead,
                detectedStickyTail: _runningStickyTail
            )
        }

        // 2. Build initial cross-axis active bin mask from the trailing scrollable portion of the frame
        var foundInitialBins = false
        let initialCrossMask = Self.BuildActiveCrossBinMask(
            prev: prevFrame,
            curr: norm,
            startSlice: (norm.primaryLen * 52) / 100,
            endSlice: (norm.primaryLen * 95) / 100,
            runningMask: _runningCrossMask,
            foundActiveBins: &foundInitialBins
        )

        // 3. Strict Sticky Header / Frozen Left Column (up to 68% of frame!) & Sticky Footer detection
        let maxHead = (norm.primaryLen * 68) / 100
        let maxTail = (norm.primaryLen * 28) / 100

        let detectedHead = Self.DetectStickyHeadStrict(prev: prevFrame, curr: norm, maxHead: maxHead, crossMask: initialCrossMask)
        let detectedTail = Self.DetectStickyTailStrict(prev: prevFrame, curr: norm, maxTail: maxTail, crossMask: initialCrossMask)

        var candidateStickyHead = _runningStickyHead
        if candidateStickyHead == 0 && detectedHead >= 16 {
            candidateStickyHead = detectedHead
        } else if candidateStickyHead > 0 && detectedHead >= 16 {
            if detectedHead < candidateStickyHead {
                candidateStickyHead = detectedHead
            } else if _frameCount <= 2 && detectedHead > candidateStickyHead {
                candidateStickyHead = detectedHead
            }
        }

        var candidateStickyTail = _runningStickyTail
        if detectedTail >= 8 {
            if candidateStickyTail == 0 || detectedTail < candidateStickyTail || abs(detectedTail - candidateStickyTail) <= 30 {
                candidateStickyTail = candidateStickyTail == 0 ? detectedTail : min(candidateStickyTail, detectedTail)
            } else if _frameCount <= 2 && detectedTail > candidateStickyTail {
                candidateStickyTail = detectedTail
            }
        }

        var activeStart = min(maxHead, max(4, candidateStickyHead + (candidateStickyHead > 0 ? 4 : 0)))
        var activeEnd = norm.primaryLen - min(maxTail, max(4, candidateStickyTail + (candidateStickyTail > 0 ? 4 : 0)))
        var activeLen = activeEnd - activeStart

        if activeLen < 40 {
            activeStart = 6
            activeEnd = norm.primaryLen - 6
            activeLen = activeEnd - activeStart
        }

        // Refine the active cross-axis bin mask specifically inside [activeStart .. activeEnd]
        var foundActiveBins = false
        let activeCrossMask = Self.BuildActiveCrossBinMask(
            prev: prevFrame,
            curr: norm,
            startSlice: activeStart,
            endSlice: activeEnd,
            runningMask: _runningCrossMask,
            foundActiveBins: &foundActiveBins
        )

        // 4. Coarse-to-Fine search for scroll offset delta
        let minDelta = 5
        let maxDelta = max(minDelta + 1, (activeLen * 80) / 100)

        var bestDelta = 0
        var bestScore = 0.0
        var isBackward = false
        var isNoMovement = false
        var matched = FindBestScrollDelta(
            prev: prevFrame,
            curr: norm,
            prevBmp: prevBitmap,
            currBmp: frame,
            activeStart: activeStart,
            activeEnd: activeEnd,
            minDelta: minDelta,
            maxDelta: maxDelta,
            activeCrossMask: activeCrossMask,
            bestDelta: &bestDelta,
            bestConfidence: &bestScore,
            isBackward: &isBackward,
            isNoMovement: &isNoMovement
        )

        if isNoMovement {
            return StitchResult(
                status: .noMovement,
                deltaPixels: 0,
                confidence: bestScore,
                totalLength: _totalCanvasLength,
                frameCount: _frameCount,
                detectedStickyHead: _runningStickyHead,
                detectedStickyTail: _runningStickyTail
            )
        }

        if isBackward {
            return StitchResult(
                status: .scrolledBackward,
                deltaPixels: bestDelta,
                confidence: bestScore,
                totalLength: _totalCanvasLength,
                frameCount: _frameCount,
                detectedStickyHead: _runningStickyHead,
                detectedStickyTail: _runningStickyTail
            )
        }

        if !matched || bestDelta < minDelta {
            // Fast-scroll intermediate frame bridge recovery
            if let lastUnmatchedFrame = _lastUnmatchedFrame, let lastUnmatchedBitmap = _lastUnmatchedBitmap {
                var bridgeDelta = 0
                var bridgeScore = 0.0
                var bridgeBack = false
                var bridgeNoMove = false
                let bridgeMatched = FindBestScrollDelta(
                    prev: lastUnmatchedFrame,
                    curr: norm,
                    prevBmp: lastUnmatchedBitmap,
                    currBmp: frame,
                    activeStart: activeStart,
                    activeEnd: activeEnd,
                    minDelta: minDelta,
                    maxDelta: maxDelta,
                    activeCrossMask: activeCrossMask,
                    bestDelta: &bridgeDelta,
                    bestConfidence: &bridgeScore,
                    isBackward: &bridgeBack,
                    isNoMovement: &bridgeNoMove
                )

                if bridgeMatched && bridgeDelta >= minDelta && bridgeScore >= 0.78 {
                    let safeRight = prevFrame.primaryLen - (prevFrame.primaryLen >= 200 ? 24 : 6)
                    let bridgeCut = min(activeEnd, safeRight)
                    let bridgeConfirmedEnd = _globalOffset + bridgeCut
                    var bridgeCopyLen = lastUnmatchedFrame.primaryLen - activeStart
                    if bridgeConfirmedEnd + bridgeCopyLen > Self.MAX_CANVAS_LENGTH {
                        bridgeCopyLen = max(0, Self.MAX_CANVAS_LENGTH - bridgeConfirmedEnd)
                    }

                    if bridgeCopyLen > 0 {
                        TrimStripsBeyond(confirmedEnd: bridgeConfirmedEnd)
                        _strips.append(CanvasStrip(
                            globalStart: bridgeConfirmedEnd,
                            length: bridgeCopyLen,
                            bitmap: lastUnmatchedBitmap.clone(),
                            srcOffset: activeStart
                        ))
                        _globalOffset = bridgeConfirmedEnd - activeStart
                        _totalCanvasLength = bridgeConfirmedEnd + bridgeCopyLen
                        _frameCount += 1
                    }

                    _prevBitmap = lastUnmatchedBitmap.clone()
                    _prevFrame = lastUnmatchedFrame
                    clearLastUnmatched()

                    bestDelta = bridgeDelta
                    bestScore = bridgeScore
                    matched = true
                }
            }

            if !matched || bestDelta < minDelta {
                _consecutiveLowConfidence += 1
                var moveFromLastUnmatched = 0.0
                if _lastUnmatchedFrame == nil || Self.HasFrameMoved(prev: _lastUnmatchedFrame!, curr: norm, zeroDiff: &moveFromLastUnmatched) {
                    clearLastUnmatched()
                    _lastUnmatchedFrame = norm
                    _lastUnmatchedBitmap = frame.clone()
                }
                return StitchResult(
                    status: .lowConfidence,
                    deltaPixels: 0,
                    confidence: bestScore,
                    totalLength: _totalCanvasLength,
                    frameCount: _frameCount,
                    detectedStickyHead: _runningStickyHead,
                    detectedStickyTail: _runningStickyTail
                )
            }
        }

        let currentPrevFrame = _prevFrame!
        let currentPrevBitmap = _prevBitmap!

        _consecutiveLowConfidence = 0
        clearLastUnmatched()
        _runningStickyHead = candidateStickyHead
        _runningStickyTail = candidateStickyTail
        if foundActiveBins {
            if _runningCrossMask == nil {
                _runningCrossMask = Array(repeating: false, count: Self.SAMPLE_COUNT)
            }
            for k in 0..<Self.SAMPLE_COUNT {
                if activeCrossMask[k] {
                    _runningCrossMask![k] = true
                }
            }
        }

        // 5. Minimum-Energy Seam Selection (FindCleanSeamSlice)
        let cleanCutInPrev = Self.FindCleanSeamSlice(
            prev: currentPrevFrame,
            curr: norm,
            activeStart: activeStart,
            activeEnd: activeEnd,
            delta: bestDelta,
            crossMask: activeCrossMask
        )

        let confirmedEnd = _globalOffset + cleanCutInPrev
        let newGlobalOffset = _globalOffset + bestDelta
        var srcStartInCurr = confirmedEnd - newGlobalOffset

        if srcStartInCurr < 0 { srcStartInCurr = 0 }
        var copyLen = norm.primaryLen - srcStartInCurr

        if confirmedEnd + copyLen > Self.MAX_CANVAS_LENGTH {
            copyLen = max(0, Self.MAX_CANVAS_LENGTH - confirmedEnd)
        }

        if copyLen > 0 {
            if _undoStack.count < 15 && !_strips.isEmpty {
                _undoStack.append(HistorySnapshot(
                    stripCountBefore: _strips.count,
                    lastStripLengthBefore: _strips[_strips.count - 1].length,
                    globalOffsetBefore: _globalOffset,
                    totalCanvasLengthBefore: _totalCanvasLength,
                    frameCountBefore: _frameCount,
                    prevBitmapClone: currentPrevBitmap.clone()
                ))
            }

            TrimStripsBeyond(confirmedEnd: confirmedEnd)

            _strips.append(CanvasStrip(
                globalStart: confirmedEnd,
                length: copyLen,
                bitmap: frame.clone(),
                srcOffset: srcStartInCurr
            ))

            _globalOffset = newGlobalOffset
            _totalCanvasLength = confirmedEnd + copyLen
            _frameCount += 1
        }

        _prevBitmap = frame.clone()
        _prevFrame = norm

        return StitchResult(
            status: .stitched,
            deltaPixels: bestDelta,
            confidence: bestScore,
            totalLength: _totalCanvasLength,
            frameCount: _frameCount,
            detectedStickyHead: activeStart,
            detectedStickyTail: norm.primaryLen - activeEnd
        )
    }

    internal static func HasFrameMoved(prev: NormalizedFrame, curr: NormalizedFrame, zeroDiff: inout Double) -> Bool {
        let start = prev.primaryLen / 12
        let end = (prev.primaryLen * 11) / 12
        var sum = 0.0
        var count = 0
        var movedSlices = 0

        for s in start..<end {
            let d = SliceDifference(a: prev, sa: s, b: curr, sb: s, crossMask: nil)
            sum += d
            count += 1

            if d > 1.1 {
                movedSlices += 1
                continue
            }

            // Also check if a localized cross-axis sub-band moved (e.g., header-only or single-row table)
            let lumaA = prev.lumaSamples[s]
            let lumaB = curr.lumaSamples[s]
            let peakA = prev.peakContrast[s]
            let peakB = curr.peakContrast[s]
            let gradA = prev.scrollGrad[s]
            let gradB = curr.scrollGrad[s]
            var changedBins = 0
            for k in 2..<(SAMPLE_COUNT - 3) {
                let rawDl = abs(Int(lumaA[k]) - Int(lumaB[k]))
                let dl = (lumaA[k] > 236 && lumaB[k] > 236) ? max(0, rawDl - 10) : max(0, rawDl - 3)
                let dp = max(0, abs(Int(peakA[k]) - Int(peakB[k])) - 9)
                let dg = abs(Int(gradA[k]) - Int(gradB[k]))
                let binDiff = dl + dp + dg
                if binDiff > 11 || dg > 9 {
                    changedBins += 1
                    if changedBins >= 2 || binDiff > 22 || dg > 16 {
                        movedSlices += 1
                        break
                    }
                }
            }
        }

        zeroDiff = count > 0 ? sum / Double(count) : 0.0
        return zeroDiff >= 1.1 || movedSlices >= 5
    }

    /// Identifies which cross-axis bins [0..SAMPLE_COUNT-1] actually changed between prev and curr.
    /// Isolates the scrolling table body and header from static top toolbars, static bottom summary rows, and opposite-moving scrollbar thumbs.
    internal static func BuildActiveCrossBinMask(
        prev: NormalizedFrame,
        curr: NormalizedFrame,
        startSlice: Int,
        endSlice: Int,
        runningMask: [Bool]?,
        foundActiveBins: inout Bool
    ) -> [Bool] {
        let span = max(1, endSlice - startSlice)
        var changedSliceCount = Array(repeating: 0, count: SAMPLE_COUNT)
        var edgesPrev = Array(repeating: 0, count: SAMPLE_COUNT)
        var edgesCurr = Array(repeating: 0, count: SAMPLE_COUNT)

        if startSlice < endSlice {
            for s in startSlice..<endSlice {
                let lA = prev.lumaSamples[s]
                let lB = curr.lumaSamples[s]
                let pA = prev.peakContrast[s]
                let pB = curr.peakContrast[s]
                let gA = prev.scrollGrad[s]
                let gB = curr.scrollGrad[s]

                for k in 1..<(SAMPLE_COUNT - 2) {
                    if gA[k] >= 6 { edgesPrev[k] += 1 }
                    if gB[k] >= 6 { edgesCurr[k] += 1 }

                    let rawDl = abs(Int(lA[k]) - Int(lB[k]))
                    let dl = (lA[k] > 236 && lB[k] > 236) ? max(0, rawDl - 10) : max(0, rawDl - 3)
                    let dp = max(0, abs(Int(pA[k]) - Int(pB[k])) - 9)
                    let dg = abs(Int(gA[k]) - Int(gB[k]))
                    let diff = dl + dp + dg
                    if diff > 7 {
                        changedSliceCount[k] += 1
                    }
                }
            }
        }

        var minEdges = Array(repeating: 0, count: SAMPLE_COUNT)
        var peakEdges = 0
        for k in 1..<(SAMPLE_COUNT - 2) {
            minEdges[k] = min(edgesPrev[k], edgesCurr[k])
            if minEdges[k] > peakEdges { peakEdges = minEdges[k] }
        }

        let threshold = max(3, span / 60)
        let minEdgeReq = max(5, peakEdges / 11)
        var rawMask = Array(repeating: false, count: SAMPLE_COUNT)
        var activeCount = 0

        for k in 1..<(SAMPLE_COUNT - 2) {
            // Require minEdges[k] >= minEdgeReq to isolate true text/feature rows and reject 2-edge scrollbar thumbs
            if changedSliceCount[k] >= threshold && minEdges[k] >= minEdgeReq {
                rawMask[k] = true
                activeCount += 1
            }
        }

        foundActiveBins = activeCount >= 1

        if !foundActiveBins && runningMask == nil {
            var all = Array(repeating: false, count: SAMPLE_COUNT)
            for k in 1..<(SAMPLE_COUNT - 3) { all[k] = true }
            return all
        }

        // Dilate by 1 bin into neighbors that also have genuine scroll-axis edges (never into scrollbar thumbs)
        var dilated = Array(repeating: false, count: SAMPLE_COUNT)
        for k in 1..<(SAMPLE_COUNT - 2) {
            if rawMask[k] ||
                (minEdges[k] >= 5 && ((k > 1 && rawMask[k - 1]) || (k + 1 < SAMPLE_COUNT - 2 && rawMask[k + 1]))) {
                dilated[k] = true
            } else if let rm = runningMask, rm[k] && minEdges[k] >= 1 {
                dilated[k] = true
            }
        }

        var finalCount = 0
        for k in 0..<SAMPLE_COUNT {
            if dilated[k] { finalCount += 1 }
        }

        if finalCount == 0, let rm = runningMask {
            return rm
        }

        return dilated
    }

    internal static func FindCleanSeamSlice(
        prev: NormalizedFrame,
        curr: NormalizedFrame,
        activeStart: Int,
        activeEnd: Int,
        delta: Int,
        crossMask: [Bool]?
    ) -> Int {
        let overlapStartInPrev = activeStart + delta
        let safeRightLimit = prev.primaryLen - (prev.primaryLen >= 200 ? 24 : 6)
        let maxCut = (safeRightLimit > overlapStartInPrev + 8) ? min(activeEnd, safeRightLimit) : activeEnd

        let searchWindow = min(44, (maxCut - overlapStartInPrev) / 2)
        if searchWindow <= 2 { return maxCut }

        let searchStart = max(overlapStartInPrev + 4, maxCut - searchWindow)
        var bestSlice = maxCut - 1
        var bestSeamCost = Double.greatestFiniteMagnitude

        if searchStart < maxCut {
            for sPrev in searchStart..<maxCut {
                let sCurr = sPrev - delta
                if sCurr < activeStart || sCurr >= curr.primaryLen { continue }

                let diff = SliceDifference(a: prev, sa: sPrev, b: curr, sb: sCurr, crossMask: crossMask)
                let gradPenalty = Double(prev.edgeEnergy[sPrev] + curr.edgeEnergy[sCurr]) * 0.45
                let textPenalty = Double(prev.textComplexity[sPrev] + curr.textComplexity[sCurr]) * 0.35

                let seamCost = diff * 2.0 + gradPenalty + textPenalty
                if seamCost < bestSeamCost {
                    bestSeamCost = seamCost
                    bestSlice = sPrev
                }
            }
        }

        return bestSlice
    }

    private func TrimStripsBeyond(confirmedEnd: Int) {
        var i = _strips.count - 1
        while i >= 0 {
            let strip = _strips[i]
            let stripEnd = strip.globalStart + strip.length
            if strip.globalStart >= confirmedEnd {
                _strips.remove(at: i)
            } else if stripEnd > confirmedEnd {
                _strips[i].length = confirmedEnd - strip.globalStart
            } else {
                break
            }
            i -= 1
        }
    }

    public func renderStitchedBitmap() -> RawBitmap? {
        guard !_strips.isEmpty else { return nil }

        let width = _direction == .vertical ? _crossDimension : _totalCanvasLength
        let height = _direction == .vertical ? _totalCanvasLength : _crossDimension
        let scale = _strips.first?.bitmap.scaleFactor ?? 1.0

        let result = RawBitmap(width: width, height: height, scaleFactor: scale)
        for s in _strips {
            if s.length <= 0 { continue }
            if _direction == .vertical {
                result.copyFrom(
                    src: s.bitmap,
                    srcX: 0,
                    srcY: s.srcOffset,
                    dstX: 0,
                    dstY: s.globalStart,
                    width: _crossDimension,
                    height: s.length
                )
            } else {
                result.copyFrom(
                    src: s.bitmap,
                    srcX: s.srcOffset,
                    srcY: 0,
                    dstX: s.globalStart,
                    dstY: 0,
                    width: s.length,
                    height: _crossDimension
                )
            }
        }
        return result
    }

    public func renderPreviewThumbnail(boxW: Int, boxH: Int) -> RawBitmap? {
        guard !_strips.isEmpty && boxW > 20 && boxH > 20 else { return nil }

        let fullW = _direction == .vertical ? _crossDimension : _totalCanvasLength
        let fullH = _direction == .vertical ? _totalCanvasLength : _crossDimension

        let scale = min(1.0, min(Double(boxW) / Double(fullW), Double(boxH) / Double(fullH)))
        let thumbW = max(1, Int((Double(fullW) * scale).rounded()))
        let thumbH = max(1, Int((Double(fullH) * scale).rounded()))

        let thumb = RawBitmap(width: thumbW, height: thumbH)
        for s in _strips {
            if s.length <= 0 { continue }
            if _direction == .vertical {
                let dy0 = Int((Double(s.globalStart) * scale).rounded())
                let dy1 = Int((Double(s.globalStart + s.length) * scale).rounded())
                let dh = max(1, dy1 - dy0)
                thumb.drawScaledFrom(
                    src: s.bitmap,
                    srcX: 0,
                    srcY: s.srcOffset,
                    srcW: _crossDimension,
                    srcH: s.length,
                    dstX: 0,
                    dstY: dy0,
                    dstW: thumbW,
                    dstH: dh
                )
            } else {
                let dx0 = Int((Double(s.globalStart) * scale).rounded())
                let dx1 = Int((Double(s.globalStart + s.length) * scale).rounded())
                let dw = max(1, dx1 - dx0)
                thumb.drawScaledFrom(
                    src: s.bitmap,
                    srcX: s.srcOffset,
                    srcY: 0,
                    srcW: s.length,
                    srcH: _crossDimension,
                    dstX: dx0,
                    dstY: 0,
                    dstW: dw,
                    dstH: thumbH
                )
            }
        }
        return thumb
    }

    private static func MaxActiveBinDiff(prev: NormalizedFrame, sa: Int, curr: NormalizedFrame, sb: Int, crossMask: [Bool]?) -> Int {
        let lA = prev.lumaSamples[sa]
        let lB = curr.lumaSamples[sb]
        let pA = prev.peakContrast[sa]
        let pB = curr.peakContrast[sb]
        let gA = prev.scrollGrad[sa]
        let gB = curr.scrollGrad[sb]

        var maxDiff = 0
        for k in 1..<(SAMPLE_COUNT - 2) {
            if let cm = crossMask, !cm[k] { continue }
            let rawDl = abs(Int(lA[k]) - Int(lB[k]))
            let dl = (lA[k] > 236 && lB[k] > 236) ? max(0, rawDl - 10) : max(0, rawDl - 3)
            let dp = max(0, abs(Int(pA[k]) - Int(pB[k])) - 8)
            let dg = abs(Int(gA[k]) - Int(gB[k]))
            let binDiff = dl + dp + dg
            if binDiff > maxDiff { maxDiff = binDiff }
        }
        return maxDiff
    }

    internal static func DetectStickyHeadStrict(prev: NormalizedFrame, curr: NormalizedFrame, maxHead: Int, crossMask: [Bool]?) -> Int {
        guard maxHead > 0 else { return 0 }
        var sliceMovedArr = Array(repeating: false, count: maxHead)
        var statTextArr = Array(repeating: false, count: maxHead)
        var totalStatCount = 0
        var totalStatTextSlices = 0
        var lastStatTextClusterSlice = 0

        for s in 0..<maxHead {
            let diff = SliceDifference(a: prev, sa: s, b: curr, sb: s, crossMask: crossMask)
            let maxBinDiff = MaxActiveBinDiff(prev: prev, sa: s, curr: curr, sb: s, crossMask: crossMask)
            let sliceMoved = (maxBinDiff >= 18 && diff > 1.8) || (diff > 3.4)
            sliceMovedArr[s] = sliceMoved

            if !sliceMoved {
                totalStatCount += 1
                if prev.textComplexity[s] >= 2 && curr.textComplexity[s] >= 2 {
                    statTextArr[s] = true
                    totalStatTextSlices += 1

                    var recentText = 0
                    let jStart = max(0, s - 23)
                    for j in jStart...s {
                        if statTextArr[j] { recentText += 1 }
                    }
                    if recentText >= 5 && totalStatCount * 100 >= (s + 1) * 72 {
                        lastStatTextClusterSlice = s + 1
                    }
                }
            }
        }

        var lastTransitionSlice = lastStatTextClusterSlice
        let stationaryTextSlices = totalStatTextSlices
        let startScan = (lastStatTextClusterSlice >= 24) ? max(0, lastStatTextClusterSlice - 4) : 0

        var movingBurstCount = 0
        var gapSlices = 0
        var firstMovingSlice = -1

        if startScan < maxHead {
            for s in startScan..<maxHead {
                if !sliceMovedArr[s] {
                    if movingBurstCount > 0 {
                        gapSlices += 1
                        if gapSlices > 3 {
                            movingBurstCount = 0
                            gapSlices = 0
                            firstMovingSlice = -1
                        }
                    }

                    if movingBurstCount == 0 {
                        if (prev.edgeEnergy[s] >= 2 && curr.edgeEnergy[s] >= 2) ||
                            (stationaryTextSlices >= 6 && prev.edgeEnergy[s] >= 1 && curr.edgeEnergy[s] >= 1) {
                            lastTransitionSlice = max(lastTransitionSlice, s + 1)
                        }
                    }
                } else {
                    if firstMovingSlice < 0 { firstMovingSlice = s }
                    movingBurstCount += 1
                    gapSlices = 0

                    if movingBurstCount >= 6 {
                        let moveStart = firstMovingSlice
                        if stationaryTextSlices >= 8 && moveStart >= 32 && moveStart - lastTransitionSlice <= 24 {
                            lastTransitionSlice = max(lastTransitionSlice, moveStart - 2)
                        } else if stationaryTextSlices >= 8 && lastTransitionSlice == lastStatTextClusterSlice && moveStart > lastTransitionSlice {
                            lastTransitionSlice = min(moveStart - 2, lastStatTextClusterSlice + 18)
                        } else if moveStart >= 12 && SliceMeanLumaDifference(f: prev, s1: 0, s2: moveStart - 1) < 1.5 &&
                                    abs(SliceMeanLuma(f: prev, s: moveStart / 2) - SliceMeanLuma(f: prev, s: min(prev.primaryLen - 1, moveStart + 20))) > 12.0 {
                            lastTransitionSlice = moveStart
                        }
                        break
                    }
                }
            }
        }

        return lastTransitionSlice >= 8 ? lastTransitionSlice : 0
    }

    internal static func DetectStickyTailStrict(prev: NormalizedFrame, curr: NormalizedFrame, maxTail: Int, crossMask: [Bool]?) -> Int {
        let len = prev.primaryLen
        var lastTransitionTail = 0
        var stationaryTextSlices = 0

        for i in 0..<maxTail {
            let s = len - 1 - i
            if s < 0 { break }
            let diff = SliceDifference(a: prev, sa: s, b: curr, sb: s, crossMask: crossMask)
            if diff <= 1.8 {
                if prev.textComplexity[s] >= 2 && curr.textComplexity[s] >= 2 {
                    stationaryTextSlices += 1
                }
                if prev.edgeEnergy[s] >= 2 && curr.edgeEnergy[s] >= 2 && (i < 22 || stationaryTextSlices >= 4) {
                    lastTransitionTail = i + 1
                }
            } else {
                if i >= 10 && SliceMeanLumaDifference(f: prev, s1: len - 1, s2: s + 1) < 1.5 &&
                    abs(SliceMeanLuma(f: prev, s: len - 1 - i / 2) - SliceMeanLuma(f: prev, s: max(0, s - 20))) > 12.0 {
                    lastTransitionTail = i
                }
                break
            }
        }

        return lastTransitionTail >= 8 ? lastTransitionTail : 0
    }

    private static func SliceMeanLuma(f: NormalizedFrame, s: Int) -> Double {
        let luma = f.lumaSamples[s]
        var sum = 0
        for i in 0..<SAMPLE_COUNT { sum += Int(luma[i]) }
        return Double(sum) / Double(SAMPLE_COUNT)
    }

    private static func SliceMeanLumaDifference(f: NormalizedFrame, s1: Int, s2: Int) -> Double {
        return abs(SliceMeanLuma(f: f, s: s1) - SliceMeanLuma(f: f, s: s2))
    }

    private static func FindActiveMaskMidpoint(crossMask: [Bool]?) -> Int {
        guard let cm = crossMask else { return SAMPLE_COUNT / 2 }
        var first = -1
        var last = -1
        for k in 0..<SAMPLE_COUNT {
            if cm[k] {
                if first < 0 { first = k }
                last = k
            }
        }
        return (first >= 0 && last > first + 3) ? ((first + last) / 2) : (SAMPLE_COUNT / 2)
    }

    private func FindBestScrollDelta(
        prev: NormalizedFrame,
        curr: NormalizedFrame,
        prevBmp: RawBitmap,
        currBmp: RawBitmap,
        activeStart: Int,
        activeEnd: Int,
        minDelta: Int,
        maxDelta: Int,
        activeCrossMask: [Bool]?,
        bestDelta: inout Int,
        bestConfidence: inout Double,
        isBackward: inout Bool,
        isNoMovement: inout Bool
    ) -> Bool {
        bestDelta = 0
        bestConfidence = 0.0
        isBackward = false
        isNoMovement = false

        let activeLen = activeEnd - activeStart
        let midBin = Self.FindActiveMaskMidpoint(crossMask: activeCrossMask)

        var totalEnergy: Int64 = 0
        var totalTextComp: Int64 = 0
        if activeStart < activeEnd {
            for s in activeStart..<activeEnd {
                totalEnergy += Int64(prev.edgeEnergy[s])
                totalTextComp += Int64(prev.textComplexity[s])
            }
        }
        let meanEnergy = Int(max(4, totalEnergy / Int64(max(1, activeLen))))
        let meanTextComp = Int(max(4, totalTextComp / Int64(max(1, activeLen))))

        let TOP_K = 14
        var topDeltas = Array(repeating: 0, count: TOP_K)
        var topCosts = Array(repeating: Double.greatestFiniteMagnitude, count: TOP_K)

        if minDelta <= maxDelta {
            for delta in minDelta...maxDelta {
                let overlapStartInPrev = activeStart + delta
                let overlapLen = activeEnd - overlapStartInPrev
                if overlapLen < 28 { break }

                let cost = Self.Evaluate1DCandidate(
                    prev: prev,
                    curr: curr,
                    activeStart: activeStart,
                    activeEnd: activeEnd,
                    delta: delta,
                    meanEnergy: meanEnergy,
                    meanTextComp: meanTextComp,
                    crossMask: activeCrossMask,
                    midBin: midBin
                )

                if cost < topCosts[TOP_K - 1] {
                    var updated = false
                    for k in 0..<TOP_K {
                        if topDeltas[k] > 0 && abs(topDeltas[k] - delta) <= 5 {
                            if cost < topCosts[k] {
                                topCosts[k] = cost
                                topDeltas[k] = delta
                                Self.SortTopK(deltas: &topDeltas, costs: &topCosts)
                            }
                            updated = true
                            break
                        }
                    }
                    if !updated {
                        topCosts[TOP_K - 1] = cost
                        topDeltas[TOP_K - 1] = delta
                        Self.SortTopK(deltas: &topDeltas, costs: &topCosts)
                    }
                }
            }
        }

        // Stage 2: High-density 2D pixel + scroll-gradient + multi-band verification on Top-K candidates
        var best2DCost = Double.greatestFiniteMagnitude
        var verifiedDelta = 0

        for k in 0..<TOP_K {
            let candDelta = topDeltas[k]
            if candDelta < minDelta { continue }

            for offset in -3...3 {
                let d = candDelta + offset
                if d < minDelta || d > maxDelta { continue }

                let pixelError = VerifyCandidate2DPixels(
                    prevNorm: prev,
                    currNorm: curr,
                    prevBmp: prevBmp,
                    currBmp: currBmp,
                    activeStart: activeStart,
                    activeEnd: activeEnd,
                    delta: d,
                    meanEnergy: meanEnergy,
                    meanTextComp: meanTextComp,
                    crossMask: activeCrossMask,
                    midBin: midBin
                )

                let adjustedCost = pixelError + (Double(d) * 0.0035)
                if adjustedCost < best2DCost {
                    best2DCost = adjustedCost
                    verifiedDelta = d
                }
            }
        }

        // Guard against zero-movement hover/focus changes and subpixel settling (< minDelta) inside the scrollable region
        var zero2DCost = Double.greatestFiniteMagnitude
        let maxZeroCheck = min(4, minDelta - 1)
        for zd in 0...maxZeroCheck {
            let zc = VerifyCandidate2DPixels(
                prevNorm: prev,
                currNorm: curr,
                prevBmp: prevBmp,
                currBmp: currBmp,
                activeStart: activeStart,
                activeEnd: activeEnd,
                delta: zd,
                meanEnergy: meanEnergy,
                meanTextComp: meanTextComp,
                crossMask: activeCrossMask,
                midBin: midBin
            )
            if zc < zero2DCost { zero2DCost = zc }
        }

        if zero2DCost < 2.0 || zero2DCost <= best2DCost * 0.96 {
            isNoMovement = true
            bestConfidence = max(0.0, 1.0 - (zero2DCost / 40.0))
            return false
        }

        // Check for accidental backward scroll (delta < 0)
        if best2DCost > 1.8 {
            let maxBack = min(160, activeLen / 2)
            var bestBack1DCost = Double.greatestFiniteMagnitude
            var bestBackDelta = 0

            if maxBack >= minDelta {
                var backDelta = -minDelta
                while backDelta >= -maxBack {
                    let backCost = Self.Evaluate1DCandidate(
                        prev: curr,
                        curr: prev,
                        activeStart: activeStart,
                        activeEnd: activeEnd,
                        delta: -backDelta,
                        meanEnergy: meanEnergy,
                        meanTextComp: meanTextComp,
                        crossMask: activeCrossMask,
                        midBin: midBin
                    )
                    if backCost < bestBack1DCost {
                        bestBack1DCost = backCost
                        bestBackDelta = backDelta
                    }
                    backDelta -= 1
                }
            }

            if bestBackDelta < 0 && bestBack1DCost + 2.0 < topCosts[0] {
                let back2DErr = VerifyCandidate2DPixels(
                    prevNorm: curr,
                    currNorm: prev,
                    prevBmp: currBmp,
                    currBmp: prevBmp,
                    activeStart: activeStart,
                    activeEnd: activeEnd,
                    delta: -bestBackDelta,
                    meanEnergy: meanEnergy,
                    meanTextComp: meanTextComp,
                    crossMask: activeCrossMask,
                    midBin: midBin
                )

                if back2DErr < 6.0 && back2DErr + 2.5 < best2DCost {
                    isBackward = true
                    bestDelta = bestBackDelta
                    bestConfidence = max(0.0, 1.0 - (back2DErr / 40.0))
                    return false
                }
            }
        }

        if verifiedDelta < minDelta || best2DCost > 24.0 {
            bestConfidence = max(0.0, 1.0 - (best2DCost / 64.0))
            return false
        }

        bestDelta = verifiedDelta
        bestConfidence = max(0.0, min(1.0, 1.0 - (best2DCost / 40.0)))
        return true
    }

    internal static func Evaluate1DCandidate(
        prev: NormalizedFrame,
        curr: NormalizedFrame,
        activeStart: Int,
        activeEnd: Int,
        delta: Int,
        meanEnergy: Int,
        meanTextComp: Int,
        crossMask: [Bool]?,
        midBin: Int
    ) -> Double {
        let overlapStartInPrev = activeStart + delta
        let overlapLen = activeEnd - overlapStartInPrev
        if overlapLen < 24 { return 255.0 }

        var weightedDiffSum = 0.0
        var weightSum = 0.0
        var textDiffSum = 0.0
        var textSliceCount = 0
        var band0WeightedSum = 0.0
        var band0WeightSum = 0.0
        var band1WeightedSum = 0.0
        var band1WeightSum = 0.0
        var bothFeatureSlices = 0
        var exactHashMatches = 0

        for sPrev in overlapStartInPrev..<activeEnd {
            let sCurr = sPrev - delta

            if prev.rowHash[sPrev] == curr.rowHash[sCurr] && prev.textComplexity[sPrev] > meanTextComp / 2 {
                exactHashMatches += 1
            }

            let prevHasFeat = prev.textComplexity[sPrev] >= meanTextComp / 2 || prev.edgeEnergy[sPrev] >= meanEnergy
            let currHasFeat = curr.textComplexity[sCurr] >= meanTextComp / 2 || curr.edgeEnergy[sCurr] >= meanEnergy
            if prevHasFeat && currHasFeat {
                bothFeatureSlices += 1
            }

            var b0SliceErr = 0.0
            var b1SliceErr = 0.0
            var b0Edges = 0
            var b1Edges = 0
            let d = SliceBandDifference(
                a: prev,
                sa: sPrev,
                b: curr,
                sb: sCurr,
                crossMask: crossMask,
                midBin: midBin,
                band0SliceErr: &b0SliceErr,
                band0EdgeCount: &b0Edges,
                band1SliceErr: &b1SliceErr,
                band1EdgeCount: &b1Edges
            )

            if b0Edges > 0 {
                let bw0 = 1.0 + Double(b0Edges) * 2.5
                band0WeightedSum += b0SliceErr * bw0
                band0WeightSum += bw0
            }
            if b1Edges > 0 {
                let bw1 = 1.0 + Double(b1Edges) * 2.5
                band1WeightedSum += b1SliceErr * bw1
                band1WeightSum += bw1
            }

            let structDiff = Double(abs(prev.edgeEnergy[sPrev] - curr.edgeEnergy[sCurr]) +
                                    abs(prev.textComplexity[sPrev] - curr.textComplexity[sCurr])) * 0.06
            let totalSliceCost = d + structDiff

            let energy = max(prev.edgeEnergy[sPrev], curr.edgeEnergy[sCurr])
            let textComp = max(prev.textComplexity[sPrev], curr.textComplexity[sCurr])

            let w = 1.0
                  + min(8.0, Double(energy) / Double(meanEnergy) * 2.0)
                  + min(24.0, Double(textComp) / Double(meanTextComp) * 8.0)

            weightedDiffSum += totalSliceCost * w
            weightSum += w

            if textComp >= meanTextComp || energy >= meanEnergy {
                textDiffSum += totalSliceCost
                textSliceCount += 1
            }
        }

        var meanWeightedDiff = weightedDiffSum / max(1.0, weightSum)

        if textSliceCount >= 3 {
            let textMeanDiff = textDiffSum / Double(textSliceCount)
            meanWeightedDiff = meanWeightedDiff * 0.30 + textMeanDiff * 0.70
        }

        if band0WeightSum >= 12.0 && band1WeightSum >= 12.0 {
            let b0Err = band0WeightedSum / band0WeightSum
            let b1Err = band1WeightedSum / band1WeightSum
            meanWeightedDiff = meanWeightedDiff * 0.45 + max(b0Err, b1Err) * 0.55
        }

        if bothFeatureSlices < 3 {
            meanWeightedDiff += Double(3 - bothFeatureSlices) * 6.0
        }

        let hashRatio = Double(exactHashMatches) / Double(overlapLen)
        return meanWeightedDiff - (hashRatio * 1.6) + (Double(delta) * 0.002)
    }

    private static func SortTopK(deltas: inout [Int], costs: inout [Double]) {
        for i in 1..<costs.count {
            let c = costs[i]
            let d = deltas[i]
            var j = i - 1
            while j >= 0 && costs[j] > c {
                costs[j + 1] = costs[j]
                deltas[j + 1] = deltas[j]
                j -= 1
            }
            costs[j + 1] = c
            deltas[j + 1] = d
        }
    }

    internal func VerifyCandidate2DPixels(
        prevNorm: NormalizedFrame,
        currNorm: NormalizedFrame,
        prevBmp: RawBitmap,
        currBmp: RawBitmap,
        activeStart: Int,
        activeEnd: Int,
        delta: Int,
        meanEnergy: Int,
        meanTextComp: Int,
        crossMask: [Bool]?,
        midBin: Int
    ) -> Double {
        let overlapStartInPrev = activeStart + delta
        let overlapLen = activeEnd - overlapStartInPrev
        if overlapLen < 20 { return 255.0 }

        let ptrPrev = prevBmp.pixels
        let ptrCurr = currBmp.pixels
        let stridePrev = prevBmp.stride
        let strideCurr = currBmp.stride

        let crossStart = min(Self.LEADING_BORDER_MARGIN, _crossDimension / 8)
        let crossEnd = max(crossStart + 8, _crossDimension - min(Self.SCROLLBAR_MARGIN, _crossDimension / 5))
        let activeCrossSpan = max(1, crossEnd - crossStart)

        var totalWeightedErr = 0.0
        var totalWeight = 0.0
        var band0WeightedErr = 0.0
        var band0Weight = 0.0
        var band1WeightedErr = 0.0
        var band1Weight = 0.0
        var importantSlicesEvaluated = 0
        var severeMismatchSlices = 0
        var matchedTextSlices = 0
        let allowSubpixel = delta >= 0

        for sPrev in overlapStartInPrev..<activeEnd {
            let sCurr = sPrev - delta
            let textComp = max(prevNorm.textComplexity[sPrev], currNorm.textComplexity[sCurr])
            let energy = max(prevNorm.edgeEnergy[sPrev], currNorm.edgeEnergy[sCurr])

            let isImportantSlice = (textComp >= meanTextComp) || (energy >= meanEnergy)
            if !isImportantSlice && ((sPrev - overlapStartInPrev) & 3) != 0 {
                continue
            }
            if isImportantSlice { importantSlicesEvaluated += 1 }

            let rowWeight = (textComp >= meanTextComp) ? 10.0 : (energy >= meanEnergy ? 4.0 : 0.5)

            var sliceDiff: Int64 = 0
            var sampleWeight: Int64 = 0
            var band0Diff: Int64 = 0
            var band0SampW: Int64 = 0
            var band0Edges = 0
            var band1Diff: Int64 = 0
            var band1SampW: Int64 = 0
            var band1Edges = 0

            if _direction == .vertical {
                let rowPrev = ptrPrev + sPrev * stridePrev
                let rowPrevM1 = (allowSubpixel && sPrev > 0) ? (ptrPrev + (sPrev - 1) * stridePrev) : rowPrev
                let rowPrevP1 = (allowSubpixel && sPrev + 1 < prevNorm.primaryLen) ? (ptrPrev + (sPrev + 1) * stridePrev) : rowPrev
                let rowCurr = ptrCurr + sCurr * strideCurr
                let rowCurrM1 = (allowSubpixel && sCurr > 0) ? (ptrCurr + (sCurr - 1) * strideCurr) : rowCurr
                let rowCurrP1 = (allowSubpixel && sCurr + 1 < prevNorm.primaryLen) ? (ptrCurr + (sCurr + 1) * strideCurr) : rowCurr
                let rowPrevUp = (sPrev >= 2) ? (ptrPrev + (sPrev - 2) * stridePrev) : rowPrev
                let rowCurrUp = (sCurr >= 2) ? (ptrCurr + (sCurr - 2) * strideCurr) : rowCurr

                var x = crossStart
                while x < crossEnd {
                    let bin = ((x - crossStart) * Self.SAMPLE_COUNT) / activeCrossSpan
                    if let cm = crossMask, bin >= 0 && bin < Self.SAMPLE_COUNT && !cm[bin] {
                        x += 2
                        continue
                    }

                    let idx = x * 4
                    let lumaPrev = Int(rowPrev[idx + 1])
                    let lumaCurr = Int(rowCurr[idx + 1])
                    let deadband = (lumaPrev > 236 && lumaCurr > 236) ? 10 : 2

                    let db = max(0, abs(Int(rowPrev[idx]) - Int(rowCurr[idx])) - deadband)
                    let dg = max(0, abs(lumaPrev - lumaCurr) - deadband)
                    let dr = max(0, abs(Int(rowPrev[idx + 2]) - Int(rowCurr[idx + 2])) - deadband)

                    let lumaPrevUp = Int(rowPrevUp[idx + 1])
                    let lumaCurrUp = Int(rowCurrUp[idx + 1])
                    let gradPrev = lumaPrev - lumaPrevUp
                    let gradCurr = lumaCurr - lumaCurrUp
                    let gradErr = abs(gradPrev - gradCurr)

                    var pixErr = db + dg + dr + gradErr
                    if allowSubpixel && pixErr > 8 {
                        let hasPrevEdge = abs(gradPrev) > 4 || abs(lumaPrev - Int(rowPrevM1[idx + 1])) > 4 || abs(lumaPrev - Int(rowPrevP1[idx + 1])) > 4
                        let hasCurrEdge = abs(gradCurr) > 4 || abs(lumaCurr - Int(rowCurrM1[idx + 1])) > 4 || abs(lumaCurr - Int(rowCurrP1[idx + 1])) > 4
                        if hasPrevEdge && hasCurrEdge {
                            // 1. Sharp prev vs blurred curr (half-step in curr)
                            let bCM = (Int(rowCurr[idx]) + Int(rowCurrM1[idx])) >> 1
                            let gCM = (lumaCurr + Int(rowCurrM1[idx + 1])) >> 1
                            let rCM = (Int(rowCurr[idx + 2]) + Int(rowCurrM1[idx + 2])) >> 1
                            let gradErrCM = min(gradErr, abs(gradPrev - (gCM - lumaCurrUp))) >> 1
                            let errCM = max(0, abs(Int(rowPrev[idx]) - bCM) - deadband)
                                      + max(0, abs(lumaPrev - gCM) - deadband)
                                      + max(0, abs(Int(rowPrev[idx + 2]) - rCM) - deadband)
                                      + gradErrCM + 2
                            if errCM < pixErr { pixErr = errCM }

                            let bCP = (Int(rowCurr[idx]) + Int(rowCurrP1[idx])) >> 1
                            let gCP = (lumaCurr + Int(rowCurrP1[idx + 1])) >> 1
                            let rCP = (Int(rowCurr[idx + 2]) + Int(rowCurrP1[idx + 2])) >> 1
                            let gradErrCP = min(abs(gradPrev - (gCP - lumaCurrUp)), abs(gradPrev - (gCP - Int(rowCurrM1[idx + 1])))) >> 1
                            let errCP = max(0, abs(Int(rowPrev[idx]) - bCP) - deadband)
                                      + max(0, abs(lumaPrev - gCP) - deadband)
                                      + max(0, abs(Int(rowPrev[idx + 2]) - rCP) - deadband)
                                      + gradErrCP + 2
                            if errCP < pixErr { pixErr = errCP }

                            // 2. Blurred prev (half-step in prev) vs sharp curr
                            let bPM = (Int(rowPrev[idx]) + Int(rowPrevM1[idx])) >> 1
                            let gPM = (lumaPrev + Int(rowPrevM1[idx + 1])) >> 1
                            let rPM = (Int(rowPrev[idx + 2]) + Int(rowPrevM1[idx + 2])) >> 1
                            let gradErrPM = min(gradErr, abs((gPM - lumaPrevUp) - gradCurr)) >> 1
                            let errPM = max(0, abs(bPM - Int(rowCurr[idx])) - deadband)
                                      + max(0, abs(gPM - lumaCurr) - deadband)
                                      + max(0, abs(rPM - Int(rowCurr[idx + 2])) - deadband)
                                      + gradErrPM + 2
                            if errPM < pixErr { pixErr = errPM }

                            let bPP = (Int(rowPrev[idx]) + Int(rowPrevP1[idx])) >> 1
                            let gPP = (lumaPrev + Int(rowPrevP1[idx + 1])) >> 1
                            let rPP = (Int(rowPrev[idx + 2]) + Int(rowPrevP1[idx + 2])) >> 1
                            let gradErrPP = min(abs((gPP - lumaPrevUp) - gradCurr), abs((gPP - Int(rowPrevM1[idx + 1])) - gradCurr)) >> 1
                            let errPP = max(0, abs(bPP - Int(rowCurr[idx])) - deadband)
                                      + max(0, abs(gPP - lumaCurr) - deadband)
                                      + max(0, abs(rPP - Int(rowCurr[idx + 2])) - deadband)
                                      + gradErrPP + 2
                            if errPP < pixErr { pixErr = errPP }
                        }
                    }

                    let isScrollEdge = (abs(gradPrev) > 5 || abs(gradCurr) > 5)
                    let w = isScrollEdge ? 10 : 1

                    sliceDiff += Int64(pixErr * w)
                    sampleWeight += Int64(3 * w)
                    if bin <= midBin {
                        band0Diff += Int64(pixErr * w)
                        band0SampW += Int64(3 * w)
                        if isScrollEdge { band0Edges += 1 }
                    } else {
                        band1Diff += Int64(pixErr * w)
                        band1SampW += Int64(3 * w)
                        if isScrollEdge { band1Edges += 1 }
                    }

                    x += 2
                }
            } else {
                let xPrevOffset = sPrev * 4
                let xPrevM1Offset = (allowSubpixel && sPrev > 0) ? ((sPrev - 1) * 4) : xPrevOffset
                let xPrevP1Offset = (allowSubpixel && sPrev + 1 < prevNorm.primaryLen) ? ((sPrev + 1) * 4) : xPrevOffset
                let xCurrOffset = sCurr * 4
                let xCurrM1Offset = (allowSubpixel && sCurr > 0) ? ((sCurr - 1) * 4) : xCurrOffset
                let xCurrP1Offset = (allowSubpixel && sCurr + 1 < prevNorm.primaryLen) ? ((sCurr + 1) * 4) : xCurrOffset
                let xPrevLeftOffset = (sPrev >= 2) ? ((sPrev - 2) * 4) : xPrevOffset
                let xCurrLeftOffset = (sCurr >= 2) ? ((sCurr - 2) * 4) : xCurrOffset

                var y = crossStart
                while y < crossEnd {
                    let bin = ((y - crossStart) * Self.SAMPLE_COUNT) / activeCrossSpan
                    if let cm = crossMask, bin >= 0 && bin < Self.SAMPLE_COUNT && !cm[bin] {
                        y += 2
                        continue
                    }

                    let rowPtrPrev = ptrPrev + y * stridePrev
                    let rowPtrCurr = ptrCurr + y * strideCurr
                    let pxPrev = rowPtrPrev + xPrevOffset
                    let pxCurr = rowPtrCurr + xCurrOffset

                    let lumaPrev = Int(pxPrev[1])
                    let lumaCurr = Int(pxCurr[1])
                    let deadband = (lumaPrev > 236 && lumaCurr > 236) ? 10 : 2

                    let db = max(0, abs(Int(pxPrev[0]) - Int(pxCurr[0])) - deadband)
                    let dg = max(0, abs(lumaPrev - lumaCurr) - deadband)
                    let dr = max(0, abs(Int(pxPrev[2]) - Int(pxCurr[2])) - deadband)

                    let lumaPrevLeft = Int((rowPtrPrev + xPrevLeftOffset)[1])
                    let lumaCurrLeft = Int((rowPtrCurr + xCurrLeftOffset)[1])
                    let gradPrev = lumaPrev - lumaPrevLeft
                    let gradCurr = lumaCurr - lumaCurrLeft
                    let gradErr = abs(gradPrev - gradCurr)

                    var pixErr = db + dg + dr + gradErr
                    if allowSubpixel && pixErr > 8 {
                        let pxCM1 = rowPtrCurr + xCurrM1Offset
                        let pxCP1 = rowPtrCurr + xCurrP1Offset
                        let pxPM1 = rowPtrPrev + xPrevM1Offset
                        let pxPP1 = rowPtrPrev + xPrevP1Offset

                        let hasPrevEdge = abs(gradPrev) > 4 || abs(lumaPrev - Int(pxPM1[1])) > 4 || abs(lumaPrev - Int(pxPP1[1])) > 4
                        let hasCurrEdge = abs(gradCurr) > 4 || abs(lumaCurr - Int(pxCM1[1])) > 4 || abs(lumaCurr - Int(pxCP1[1])) > 4
                        if hasPrevEdge && hasCurrEdge {
                            // 1. Sharp prev vs blurred curr (half-step in curr)
                            let bCM = (Int(pxCurr[0]) + Int(pxCM1[0])) >> 1
                            let gCM = (lumaCurr + Int(pxCM1[1])) >> 1
                            let rCM = (Int(pxCurr[2]) + Int(pxCM1[2])) >> 1
                            let gradErrCM = min(gradErr, abs(gradPrev - (gCM - lumaCurrLeft))) >> 1
                            let errCM = max(0, abs(Int(pxPrev[0]) - bCM) - deadband)
                                      + max(0, abs(lumaPrev - gCM) - deadband)
                                      + max(0, abs(Int(pxPrev[2]) - rCM) - deadband)
                                      + gradErrCM + 2
                            if errCM < pixErr { pixErr = errCM }

                            let bCP = (Int(pxCurr[0]) + Int(pxCP1[0])) >> 1
                            let gCP = (lumaCurr + Int(pxCP1[1])) >> 1
                            let rCP = (Int(pxCurr[2]) + Int(pxCP1[2])) >> 1
                            let gradErrCP = min(abs(gradPrev - (gCP - lumaCurrLeft)), abs(gradPrev - (gCP - Int(pxCM1[1])))) >> 1
                            let errCP = max(0, abs(Int(pxPrev[0]) - bCP) - deadband)
                                      + max(0, abs(lumaPrev - gCP) - deadband)
                                      + max(0, abs(Int(pxPrev[2]) - rCP) - deadband)
                                      + gradErrCP + 2
                            if errCP < pixErr { pixErr = errCP }

                            // 2. Blurred prev (half-step in prev) vs sharp curr
                            let bPM = (Int(pxPrev[0]) + Int(pxPM1[0])) >> 1
                            let gPM = (lumaPrev + Int(pxPM1[1])) >> 1
                            let rPM = (Int(pxPrev[2]) + Int(pxPM1[2])) >> 1
                            let gradErrPM = min(gradErr, abs((gPM - lumaPrevLeft) - gradCurr)) >> 1
                            let errPM = max(0, abs(bPM - Int(pxCurr[0])) - deadband)
                                      + max(0, abs(gPM - lumaCurr) - deadband)
                                      + max(0, abs(rPM - Int(pxCurr[2])) - deadband)
                                      + gradErrPM + 2
                            if errPM < pixErr { pixErr = errPM }

                            let bPP = (Int(pxPrev[0]) + Int(pxPP1[0])) >> 1
                            let gPP = (lumaPrev + Int(pxPP1[1])) >> 1
                            let rPP = (Int(pxPrev[2]) + Int(pxPP1[2])) >> 1
                            let gradErrPP = min(abs((gPP - lumaPrevLeft) - gradCurr), abs((gPP - Int(pxPM1[1])) - gradCurr)) >> 1
                            let errPP = max(0, abs(bPP - Int(pxCurr[0])) - deadband)
                                      + max(0, abs(gPP - lumaCurr) - deadband)
                                      + max(0, abs(rPP - Int(pxCurr[2])) - deadband)
                                      + gradErrPP + 2
                            if errPP < pixErr { pixErr = errPP }
                        }
                    }

                    let isScrollEdge = (abs(gradPrev) > 5 || abs(gradCurr) > 5)
                    let w = isScrollEdge ? 10 : 1

                    sliceDiff += Int64(pixErr * w)
                    sampleWeight += Int64(3 * w)
                    if bin <= midBin {
                        band0Diff += Int64(pixErr * w)
                        band0SampW += Int64(3 * w)
                        if isScrollEdge { band0Edges += 1 }
                    } else {
                        band1Diff += Int64(pixErr * w)
                        band1SampW += Int64(3 * w)
                        if isScrollEdge { band1Edges += 1 }
                    }

                    y += 2
                }
            }

            let avgSliceErr = sampleWeight > 0 ? Double(sliceDiff) / Double(sampleWeight) : 0.0
            if sampleWeight > 0 {
                totalWeightedErr += avgSliceErr * rowWeight
                totalWeight += rowWeight
            }
            let b0SliceAvg = (band0SampW > 0 && band0Edges > 0) ? Double(band0Diff) / Double(band0SampW) : 0.0
            if band0SampW > 0 && band0Edges > 0 {
                let b0SliceW = 1.0 + Double(band0Edges) * 2.5
                band0WeightedErr += b0SliceAvg * b0SliceW
                band0Weight += b0SliceW
            }
            let b1SliceAvg = (band1SampW > 0 && band1Edges > 0) ? Double(band1Diff) / Double(band1SampW) : 0.0
            if band1SampW > 0 && band1Edges > 0 {
                let b1SliceW = 1.0 + Double(band1Edges) * 2.5
                band1WeightedErr += b1SliceAvg * b1SliceW
                band1Weight += b1SliceW
            }

            if isImportantSlice && (avgSliceErr > 16.0 || (band0Edges >= 2 && b0SliceAvg > 18.0) || (band1Edges >= 2 && b1SliceAvg > 18.0)) {
                severeMismatchSlices += 1
            }
            if prevNorm.textComplexity[sPrev] >= meanTextComp / 2 && currNorm.textComplexity[sCurr] >= meanTextComp / 2 && avgSliceErr < 14.0 {
                matchedTextSlices += 1
            }
        }

        var finalErr = totalWeight > 0 ? (totalWeightedErr / totalWeight) : 255.0
        if band0Weight >= 10.0 && band1Weight >= 10.0 {
            let b0Err = band0WeightedErr / band0Weight
            let b1Err = band1WeightedErr / band1Weight
            finalErr = finalErr * 0.45 + max(b0Err, b1Err) * 0.55
        }
        if severeMismatchSlices >= 4 && importantSlicesEvaluated > 0 {
            finalErr += (Double(severeMismatchSlices) / Double(importantSlicesEvaluated)) * 18.0
        }
        if importantSlicesEvaluated < 3 && delta >= 5 {
            finalErr += Double(3 - importantSlicesEvaluated) * 5.0
        }
        if delta >= 5 && matchedTextSlices < 3 && importantSlicesEvaluated < 6 {
            finalErr += Double(3 - matchedTextSlices) * 4.0
        }
        return finalErr
    }

    internal static func SliceBandDifference(
        a: NormalizedFrame,
        sa: Int,
        b: NormalizedFrame,
        sb: Int,
        crossMask: [Bool]?,
        midBin: Int,
        band0SliceErr: inout Double,
        band0EdgeCount: inout Int,
        band1SliceErr: inout Double,
        band1EdgeCount: inout Int
    ) -> Double {
        let lumaA = a.lumaSamples[sa]
        let lumaAM1 = (sa > 0 && sa != sb) ? a.lumaSamples[sa - 1] : lumaA
        let lumaAP1 = (sa + 1 < a.primaryLen && sa != sb) ? a.lumaSamples[sa + 1] : lumaA
        let lumaB = b.lumaSamples[sb]
        let lumaBM1 = (sb > 0 && sa != sb) ? b.lumaSamples[sb - 1] : lumaB
        let lumaBP1 = (sb + 1 < b.primaryLen && sa != sb) ? b.lumaSamples[sb + 1] : lumaB
        let peakA = a.peakContrast[sa]
        let peakB = b.peakContrast[sb]
        let gradA = a.scrollGrad[sa]
        let gradAM1 = (sa > 0 && sa != sb) ? a.scrollGrad[sa - 1] : gradA
        let gradAP1 = (sa + 1 < a.primaryLen && sa != sb) ? a.scrollGrad[sa + 1] : gradA
        let gradB = b.scrollGrad[sb]
        let gradBM1 = (sb > 0 && sa != sb) ? b.scrollGrad[sb - 1] : gradB
        let gradBP1 = (sb + 1 < b.primaryLen && sa != sb) ? b.scrollGrad[sb + 1] : gradB
        let chromaA = a.chromaSamples[sa]
        let chromaB = b.chromaSamples[sb]

        var diff = 0
        var weightSum = 0
        var b0Diff = 0
        var b0W = 0
        var b1Diff = 0
        var b1W = 0
        band0EdgeCount = 0
        band1EdgeCount = 0

        for i in 0..<SAMPLE_COUNT {
            if let cm = crossMask, !cm[i] { continue }
            let rawDl = abs(Int(lumaA[i]) - Int(lumaB[i]))
            let dl = (lumaA[i] > 236 && lumaB[i] > 236) ? max(0, rawDl - 10) : max(0, rawDl - 2)
            let dp = max(0, abs(Int(peakA[i]) - Int(peakB[i])) - 6)
            let dg = abs(Int(gradA[i]) - Int(gradB[i]))
            let dc = max(0, (abs(Int(chromaA[i]) - Int(chromaB[i])) >> 1) - 6)

            var binCost = dl + dp + dg + dc
            if sa != sb && binCost > 8 {
                let hasEdgeA = gradA[i] >= 4 || gradAM1[i] >= 4 || gradAP1[i] >= 4 || peakA[i] >= 10
                let hasEdgeB = gradB[i] >= 4 || gradBM1[i] >= 4 || gradBP1[i] >= 4 || peakB[i] >= 10
                if hasEdgeA && hasEdgeB {
                    let dpHalf = dp >> 1

                    let lBM = (Int(lumaB[i]) + Int(lumaBM1[i])) >> 1
                    let gBM = (Int(gradB[i]) + Int(gradBM1[i])) >> 1
                    let costBM = max(0, abs(Int(lumaA[i]) - lBM) - 3) + dpHalf + (abs(Int(gradA[i]) - gBM) >> 1) + dc + 2
                    if costBM < binCost { binCost = costBM }

                    let lBP = (Int(lumaB[i]) + Int(lumaBP1[i])) >> 1
                    let gBP = (Int(gradB[i]) + Int(gradBP1[i])) >> 1
                    let costBP = max(0, abs(Int(lumaA[i]) - lBP) - 3) + dpHalf + (abs(Int(gradA[i]) - gBP) >> 1) + dc + 2
                    if costBP < binCost { binCost = costBP }

                    let lAM = (Int(lumaA[i]) + Int(lumaAM1[i])) >> 1
                    let gAM = (Int(gradA[i]) + Int(gradAM1[i])) >> 1
                    let costAM = max(0, abs(lAM - Int(lumaB[i])) - 3) + dpHalf + (abs(gAM - Int(gradB[i])) >> 1) + dc + 2
                    if costAM < binCost { binCost = costAM }

                    let lAP = (Int(lumaA[i]) + Int(lumaAP1[i])) >> 1
                    let gAP = (Int(gradA[i]) + Int(gradAP1[i])) >> 1
                    let costAP = max(0, abs(lAP - Int(lumaB[i])) - 3) + dpHalf + (abs(gAP - Int(gradB[i])) >> 1) + dc + 2
                    if costAP < binCost { binCost = costAP }
                }
            }

            let isScrollEdge = (gradA[i] >= 6 || gradB[i] >= 6)
            let w = isScrollEdge ? 6 : 1
            diff += binCost * w
            weightSum += w

            if i <= midBin {
                b0Diff += binCost * w
                b0W += w
                if isScrollEdge { band0EdgeCount += 1 }
            } else {
                b1Diff += binCost * w
                b1W += w
                if isScrollEdge { band1EdgeCount += 1 }
            }
        }

        band0SliceErr = b0W > 0 ? Double(b0Diff) / Double(b0W) : 0.0
        band1SliceErr = b1W > 0 ? Double(b1Diff) / Double(b1W) : 0.0
        return weightSum > 0 ? Double(diff) / Double(weightSum) : 0.0
    }

    internal static func SliceDifference(a: NormalizedFrame, sa: Int, b: NormalizedFrame, sb: Int, crossMask: [Bool]?) -> Double {
        var b0e = 0.0
        var b1e = 0.0
        var b0c = 0
        var b1c = 0
        return SliceBandDifference(
            a: a,
            sa: sa,
            b: b,
            sb: sb,
            crossMask: crossMask,
            midBin: SAMPLE_COUNT / 2,
            band0SliceErr: &b0e,
            band0EdgeCount: &b0c,
            band1SliceErr: &b1e,
            band1EdgeCount: &b1c
        )
    }

    internal static func ExtractNormalizedFrame(bmp: RawBitmap, direction: ScrollDirection) -> NormalizedFrame {
        let width = bmp.width
        let height = bmp.height

        let primaryLen = direction == .vertical ? height : width
        let crossLen = direction == .vertical ? width : height

        let norm = NormalizedFrame(primaryLen: primaryLen, crossLen: crossLen)

        let crossStart = min(LEADING_BORDER_MARGIN, crossLen / 8)
        let crossEnd = max(crossStart + 4, crossLen - min(SCROLLBAR_MARGIN, crossLen / 5))
        let activeCrossSpan = max(1, crossEnd - crossStart)

        let scan0 = bmp.pixels
        let stride = bmp.stride

        for p in 0..<primaryLen {
            var luma = Array(repeating: UInt8(0), count: SAMPLE_COUNT)
            var peak = Array(repeating: UInt8(0), count: SAMPLE_COUNT)
            var sgrad = Array(repeating: UInt8(0), count: SAMPLE_COUNT)
            var chroma = Array(repeating: Int16(0), count: SAMPLE_COUNT)

            var scrollAxisEnergySum = 0
            var textComplexitySum = 0
            var hash: UInt64 = 14695981039346656037

            for k in 0..<SAMPLE_COUNT {
                let c0 = crossStart + (k * activeCrossSpan) / SAMPLE_COUNT
                var c1 = crossStart + ((k + 1) * activeCrossSpan) / SAMPLE_COUNT
                if c1 <= c0 { c1 = c0 + 1 }

                let step = (c1 - c0) > 8 ? 2 : 1
                var sumY = 0
                var sumC = 0
                var minY = 255
                var maxY = 0
                var count = 0

                var c = c0
                while c < c1 {
                    let px = (direction == .vertical)
                        ? (scan0 + p * stride + c * 4)
                        : (scan0 + c * stride + p * 4)

                    let b = Int(px[0])
                    let g = Int(px[1])
                    let r = Int(px[2])

                    let yVal = (r * 77 + g * 150 + b * 29) >> 8
                    let cVal = (r - b) + (g - b)

                    sumY += yVal
                    sumC += cVal
                    if yVal < minY { minY = yVal }
                    if yVal > maxY { maxY = yVal }
                    count += 1
                    c += step
                }

                let meanY = sumY / count
                let effectiveLuma = UInt8(clamping: (meanY * 2 + minY) / 3)
                let contrastY = UInt8(clamping: maxY - minY)
                let avgC = Int16(clamping: sumC / count)

                luma[k] = effectiveLuma
                peak[k] = contrastY
                chroma[k] = avgC

                var gradP: UInt8 = 0
                if p > 0 {
                    let dl = abs(Int(effectiveLuma) - Int(norm.lumaSamples[p - 1][k]))
                    let dp = abs(Int(contrastY) - Int(norm.peakContrast[p - 1][k]))
                    gradP = UInt8(min(255, dl + (dp >> 1)))
                    scrollAxisEnergySum += Int(gradP)
                }
                sgrad[k] = gradP

                if k > 0 {
                    let gradVar = abs(Int(gradP) - Int(sgrad[k - 1]))
                    if gradP > 5 {
                        textComplexitySum += Int(gradP) + gradVar
                    }
                }

                let quantized = UInt64((effectiveLuma >> 2) ^ (contrastY >> 2) ^ (gradP >> 2))
                hash ^= quantized
                hash = hash &* 1099511628211
            }

            norm.lumaSamples[p] = luma
            norm.peakContrast[p] = peak
            norm.scrollGrad[p] = sgrad
            norm.chromaSamples[p] = chroma
            norm.edgeEnergy[p] = scrollAxisEnergySum / 8
            norm.textComplexity[p] = textComplexitySum / 8
            norm.rowHash[p] = hash
        }

        return norm
    }
}
