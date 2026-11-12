import AppKit
import Foundation

public enum AppLanguage: String, CaseIterable {
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case en = "en"
    case ja = "ja"
    case ko = "ko"
    case fr = "fr"
    case de = "de"
    case es = "es"
    case pt = "pt"
    case ru = "ru"

    public var displayName: String {
        switch self {
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .en: return "English"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .fr: return "Français"
        case .de: return "Deutsch"
        case .es: return "Español"
        case .pt: return "Português"
        case .ru: return "Русский"
        }
    }

    public static func fromCode(_ code: String) -> AppLanguage? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("zh-hant") || trimmed.hasPrefix("zh_tw") || trimmed.hasPrefix("zh-tw")
            || trimmed.hasPrefix("zh_hk") || trimmed.hasPrefix("zh-hk") || trimmed.hasPrefix("zh-mo") {
            return .zhHant
        }
        if trimmed.hasPrefix("zh") { return .zhHans }
        if trimmed.hasPrefix("en") { return .en }
        if trimmed.hasPrefix("ja") { return .ja }
        if trimmed.hasPrefix("ko") { return .ko }
        if trimmed.hasPrefix("fr") { return .fr }
        if trimmed.hasPrefix("de") { return .de }
        if trimmed.hasPrefix("es") { return .es }
        if trimmed.hasPrefix("pt") { return .pt }
        if trimmed.hasPrefix("ru") { return .ru }
        return nil
    }

    public static func detectSystemDefault() -> AppLanguage {
        if let first = Locale.preferredLanguages.first, let detected = fromCode(first) {
            return detected
        }
        return .zhHans
    }
}

public enum L10n {
    private static let prefKeyLanguage = "SpanShot.Language"

    public static var current: AppLanguage = loadInitialLanguage()

    private static func loadInitialLanguage() -> AppLanguage {
        if let saved = UserDefaults.standard.string(forKey: prefKeyLanguage),
           let lang = AppLanguage.fromCode(saved) {
            return lang
        }
        return AppLanguage.detectSystemDefault()
    }

    public static func setLanguage(_ lang: AppLanguage) {
        current = lang
        UserDefaults.standard.set(lang.rawValue, forKey: prefKeyLanguage)
    }

    public static func tr(
        _ zhHans: String,
        _ zhHant: String,
        _ en: String,
        ja: String? = nil,
        ko: String? = nil,
        fr: String? = nil,
        de: String? = nil,
        es: String? = nil,
        pt: String? = nil,
        ru: String? = nil
    ) -> String {
        switch current {
        case .zhHans: return zhHans
        case .zhHant: return zhHant
        case .en: return en
        case .ja: return ja ?? en
        case .ko: return ko ?? en
        case .fr: return fr ?? en
        case .de: return de ?? en
        case .es: return es ?? en
        case .pt: return pt ?? en
        case .ru: return ru ?? en
        }
    }

    // MARK: - MainForm UI
    public static var startCapture: String {
        tr(
            "开始截图", "開始截圖", "Start Capture",
            ja: "キャプチャ開始", ko: "캡처 시작",
            fr: "Capturer", de: "Aufnahme starten",
            es: "Iniciar captura", pt: "Iniciar captura",
            ru: "Начать снимок"
        )
    }
    public static var pressKeysPrompt: String {
        tr(
            "请按键...", "請按鍵...", "Press keys...",
            ja: "キーを入力...", ko: "단축키 입력...",
            fr: "Appuyez...", de: "Tasten drücken...",
            es: "Pulse teclas...", pt: "Pressione...",
            ru: "Нажмите..."
        )
    }

    public static var sectionCaptureAndSave: String {
        tr(
            "截图与保存", "截圖與儲存", "Capture & Save",
            ja: "キャプチャと保存", ko: "캡처 및 저장",
            fr: "Capture et sauvegarde", de: "Aufnahme & Speichern",
            es: "Captura y guardado", pt: "Captura e salvamento",
            ru: "Снимок и сохранение"
        )
    }
    public static var windowShadowLabel: String {
        tr(
            "窗口截图", "視窗截圖", "Window Capture",
            ja: "ウィンドウ撮影", ko: "창 캡처",
            fr: "Capture de fenêtre", de: "Fensteraufnahme",
            es: "Captura de ventana", pt: "Captura de janela",
            ru: "Снимок окна"
        )
    }
    public static var windowShadowHint: String {
        tr(
            "保留圆角与阴影", "保留圓角與陰影", "Keep corners & shadow",
            ja: "角丸と影を保持", ko: "둥근 모서리 및 그림자 유지",
            fr: "Coins et ombre", de: "Ecken & Schatten",
            es: "Bordes y sombra", pt: "Cantos e sombra",
            ru: "Углы и тень"
        )
    }
    public static var quickCopyLabel: String {
        tr(
            "快捷截图", "快捷截圖", "Quick Copy",
            ja: "クイックコピー", ko: "빠른 복사",
            fr: "Copie rapide", de: "Schnellkopie",
            es: "Copia rápida", pt: "Cópia rápida",
            ru: "Быстрое копирование"
        )
    }
    public static var quickCopyHint: String {
        tr(
            "只复制不预览", "只複製不預覽", "Copy without preview",
            ja: "プレビューなし", ko: "미리보기 없이 복사",
            fr: "Sans aperçu", de: "Ohne Vorschau",
            es: "Sin vista previa", pt: "Sem prévia",
            ru: "Без предпросмотра"
        )
    }
    public static var autoSaveLabel: String {
        tr(
            "自动保存", "自動儲存", "Auto Save",
            ja: "自動保存", ko: "자동 저장",
            fr: "Sauvegarde auto", de: "Auto-Speichern",
            es: "Autoguardado", pt: "Salvar auto",
            ru: "Автосохранение"
        )
    }
    public static var btnOpenDir: String {
        tr(
            "打开", "打開", "Open",
            ja: "開く", ko: "열기",
            fr: "Ouvrir", de: "Öffnen",
            es: "Abrir", pt: "Abrir",
            ru: "Откр."
        )
    }
    public static var btnChangeDir: String {
        tr(
            "更改", "更改", "Change",
            ja: "変更", ko: "변경",
            fr: "Changer", de: "Ändern",
            es: "Cambiar", pt: "Alterar",
            ru: "Изм."
        )
    }
    public static var btnSelectDir: String {
        tr(
            "选择目录", "選擇目錄", "Select...",
            ja: "フォルダ選択", ko: "폴더 선택",
            fr: "Choisir...", de: "Wählen...",
            es: "Elegir...", pt: "Selecionar...",
            ru: "Выбрать..."
        )
    }
    public static var autoSaveNoDirNote: String {
        tr(
            "未指定目录，开启时将提示选择文件夹",
            "未指定目錄，開啟時將提示選擇資料夾",
            "No folder selected (will prompt when enabled)",
            ja: "フォルダ未指定（有効化時に選択します）",
            ko: "폴더 미지정 (활성화 시 폴더 선택)",
            fr: "Aucun dossier défini (demandé à l'activation)",
            de: "Kein Ordner gewählt (Auswahl beim Aktivieren)",
            es: "Sin carpeta (se solicitará al activar)",
            pt: "Sem pasta definida (solicitará ao ativar)",
            ru: "Папка не выбрана (запрос при включении)"
        )
    }
    public static func autoSaveDirPrefix(_ path: String) -> String {
        tr(
            "目录: \(path)", "目錄: \(path)", "Folder: \(path)",
            ja: "保存先: \(path)", ko: "폴더: \(path)",
            fr: "Dossier: \(path)", de: "Ordner: \(path)",
            es: "Carpeta: \(path)", pt: "Pasta: \(path)",
            ru: "Папка: \(path)"
        )
    }

    public static var sectionSystemAndBg: String {
        tr(
            "系统与后台", "系統與背景", "System & Background",
            ja: "システムとバックグラウンド", ko: "시스템 및 백그라운드",
            fr: "Système et arrière-plan", de: "System & Hintergrund",
            es: "Sistema y segundo plano", pt: "Sistema e segundo plano",
            ru: "Система и фон"
        )
    }
    public static var keepAliveLabel: String {
        tr(
            "常驻后台", "常駐背景", "Keep in Background",
            ja: "バックグラウンド常駐", ko: "백그라운드 유지",
            fr: "Garder en arrière-plan", de: "Im Hintergrund halten",
            es: "Mantener en 2.º plano", pt: "Manter em 2.º plano",
            ru: "Работать в фоне"
        )
    }
    public static var keepAliveHint: String {
        tr(
            "关闭主窗口不退出", "關閉主視窗不退出", "Minimize on close",
            ja: "閉じても終了しない", ko: "창 닫을 때 최소화",
            fr: "Réduire à la fermeture", de: "Beim Schließen minimieren",
            es: "Minimizar al cerrar", pt: "Minimizar ao fechar",
            ru: "Сворачивать при закрытии"
        )
    }
    public static var hideStatusBarLabel: String {
        tr(
            "隐藏状态栏图标", "隱藏狀態列圖示", "Hide Menu Bar Icon",
            ja: "メニューバーアイコンを隠す", ko: "메뉴 막대 아이콘 숨기기",
            fr: "Masquer l'icône de barre", de: "Menüleisten-Icon ausblenden",
            es: "Ocultar icono de barra", pt: "Ocultar ícone da barra",
            ru: "Скрыть значок в меню"
        )
    }
    public static var hideStatusBarHint: String {
        tr(
            "仅用快捷键唤醒", "僅用快捷鍵喚醒", "Hotkey only",
            ja: "ショートカットのみ", ko: "단축키로만 호출",
            fr: "Raccourci seul", de: "Nur per Kurzbefehl",
            es: "Solo con atajo", pt: "Apenas atalho",
            ru: "Только по хоткею"
        )
    }
    public static var autoStartLabel: String {
        tr(
            "开机自启", "開機自啟", "Launch at Login",
            ja: "ログイン時に起動", ko: "로그인 시 자동 실행",
            fr: "Lancer à la connexion", de: "Bei Anmeldung starten",
            es: "Iniciar al encender", pt: "Iniciar no login",
            ru: "Запуск при входе"
        )
    }
    public static var autoStartHint: String {
        tr(
            "登录系统时自动启动", "登入系統時自動啟動", "Start automatically",
            ja: "自動スタート", ko: "시스템 시작 시 실행",
            fr: "Démarrage auto", de: "Automatisch starten",
            es: "Inicio automático", pt: "Início automático",
            ru: "Автозапуск"
        )
    }

    // MARK: - Update & Notices
    public static var checkUpdate: String {
        tr(
            "检查更新", "檢查更新", "Check for Updates",
            ja: "アップデートを確認", ko: "업데이트 확인",
            fr: "Vérifier les mises à jour", de: "Nach Updates suchen",
            es: "Buscar actualizaciones", pt: "Verificar atualizações",
            ru: "Проверить обновления"
        )
    }
    public static var checkingUpdate: String {
        tr(
            "正在检查更新...", "正在檢查更新...", "Checking for updates...",
            ja: "アップデートを確認中...", ko: "업데이트 확인 중...",
            fr: "Recherche de mises à jour...", de: "Suche nach Updates...",
            es: "Buscando actualizaciones...", pt: "Verificando atualizações...",
            ru: "Проверка обновлений..."
        )
    }
    public static func pullingUpdate(_ ver: String, _ pct: Int) -> String {
        tr(
            "正在拉取 v\(ver)... \(pct)%", "正在拉取 v\(ver)... \(pct)%", "Downloading v\(ver)... \(pct)%",
            ja: "v\(ver) をダウンロード中... \(pct)%", ko: "v\(ver) 다운로드 중... \(pct)%",
            fr: "Téléchargement v\(ver)... \(pct)%", de: "Lade v\(ver)... \(pct)%",
            es: "Descargando v\(ver)... \(pct)%", pt: "Baixando v\(ver)... \(pct)%",
            ru: "Загрузка v\(ver)... \(pct)%"
        )
    }
    public static func newVersionFoundPrefix(_ ver: String) -> String {
        tr(
            "发现新版本 v\(ver) · ", "發現新版本 v\(ver) · ", "New version v\(ver) · ",
            ja: "新バージョン v\(ver) · ", ko: "새 버전 v\(ver) · ",
            fr: "Nouvelle version v\(ver) · ", de: "Neue Version v\(ver) · ",
            es: "Nueva versión v\(ver) · ", pt: "Nova versão v\(ver) · ",
            ru: "Новая версия v\(ver) · "
        )
    }
    public static var goToDownload: String {
        tr(
            "前往下载", "前往下載", "Download",
            ja: "ダウンロード", ko: "다운로드",
            fr: "Télécharger", de: "Herunterladen",
            es: "Descargar", pt: "Baixar",
            ru: "Скачать"
        )
    }
    public static var pullUpdateNow: String {
        tr(
            "拉取更新", "拉取更新", "Update Now",
            ja: "今すぐ更新", ko: "지금 업데이트",
            fr: "Mettre à jour", de: "Jetzt aktualisieren",
            es: "Actualizar", pt: "Atualizar",
            ru: "Обновить"
        )
    }
    public static var ignoreUpdate: String {
        tr(
            "忽略", "忽略", "Ignore",
            ja: "無視", ko: "무시",
            fr: "Ignorer", de: "Ignorieren",
            es: "Omitir", pt: "Ignorar",
            ru: "Скрыть"
        )
    }

    public static func languageSwitchedNotice(_ lang: AppLanguage) -> String {
        switch lang {
        case .zhHans: return "语言已切换为 简体中文"
        case .zhHant: return "語言已切換為 繁體中文"
        case .en: return "Language switched to English"
        case .ja: return "言語を日本語に切り替えました"
        case .ko: return "언어가 한국어로 변경되었습니다"
        case .fr: return "Langue changée en Français"
        case .de: return "Sprache auf Deutsch geändert"
        case .es: return "Idioma cambiado a Español"
        case .pt: return "Idioma alterado para Português"
        case .ru: return "Язык изменён на Русский"
        }
    }

    public static func statusBarHiddenNotice(_ hidden: Bool) -> String {
        if hidden {
            return tr(
                "已隐藏顶部状态栏图标（后台仍常驻运行）",
                "已隱藏頂部狀態列圖示（背景仍常駐執行）",
                "Menu bar icon hidden (still running in background)",
                ja: "メニューバーアイコンを非表示にしました",
                ko: "메뉴 막대 아이콘을 숨겼습니다",
                fr: "Icône de la barre des menus masquée",
                de: "Menüleisten-Icon ausgeblendet",
                es: "Icono de la barra de menús oculto",
                pt: "Ícone da barra de menus oculto",
                ru: "Значок в строке меню скрыт"
            )
        } else {
            return tr(
                "已恢复显示顶部状态栏图标",
                "已恢復顯示頂部狀態列圖示",
                "Menu bar icon restored",
                ja: "メニューバーアイコンを表示しました",
                ko: "메뉴 막대 아이콘을 표시했습니다",
                fr: "Icône de la barre des menus affichée",
                de: "Menüleisten-Icon wiederhergestellt",
                es: "Icono de la barra de menús restaurado",
                pt: "Ícone da barra de menus restaurado",
                ru: "Значок в строке меню восстановлен"
            )
        }
    }

    public static func windowShadowNotice(_ enabled: Bool) -> String {
        if enabled {
            return tr(
                "已开启窗口圆角阴影截图", "已開啟視窗圓角陰影截圖", "Window shadow capture enabled",
                ja: "ウィンドウ角丸・影キャプチャを有効にしました", ko: "창 둥근 모서리 및 그림자 캡처 켜짐",
                fr: "Capture avec ombre de fenêtre activée", de: "Fensterschatten-Aufnahme aktiviert",
                es: "Captura con sombra de ventana activada", pt: "Captura com sombra da janela ativada",
                ru: "Снимок окна с тенью включён"
            )
        } else {
            return tr(
                "已关闭窗口圆角阴影截图", "已關閉視窗圓角陰影截圖", "Window shadow capture disabled",
                ja: "ウィンドウ角丸・影キャプチャを無効にしました", ko: "창 둥근 모서리 및 그림자 캡처 꺼짐",
                fr: "Capture avec ombre de fenêtre désactivée", de: "Fensterschatten-Aufnahme deaktiviert",
                es: "Captura con sombra de ventana desactivada", pt: "Captura com sombra da janela desativada",
                ru: "Снимок окна с тенью выключен"
            )
        }
    }

    public static func autoStartNotice(_ enabled: Bool) -> String {
        if enabled {
            return tr(
                "已开启开机自启", "已開啟開機自啟", "Launch at Login enabled",
                ja: "ログイン時に起動を有効にしました", ko: "로그인 시 자동 실행 켜짐",
                fr: "Lancement à la connexion activé", de: "Start bei Anmeldung aktiviert",
                es: "Inicio automático activado", pt: "Iniciar no login ativado",
                ru: "Запуск при входе включён"
            )
        } else {
            return tr(
                "已关闭开机自启", "已關閉開機自啟", "Launch at Login disabled",
                ja: "ログイン時に起動を無効にしました", ko: "로그인 시 자동 실행 꺼짐",
                fr: "Lancement à la connexion désactivé", de: "Start bei Anmeldung deaktiviert",
                es: "Inicio automático desactivado", pt: "Iniciar no login desativado",
                ru: "Запуск при входе выключен"
            )
        }
    }

    public static var autoStartFailedNotice: String {
        tr(
            "设置开机自启失败", "設定開機自啟失敗", "Failed to update Launch at Login",
            ja: "自動起動の設定に失敗しました", ko: "자동 실행 설정 실패",
            fr: "Échec du réglage de démarrage", de: "Autostart-Einstellung fehlgeschlagen",
            es: "Error al configurar inicio automático", pt: "Falha ao configurar início automático",
            ru: "Ошибка настройки автозапуска"
        )
    }
    public static var saveDirInvalidNotice: String {
        tr(
            "保存目录不存在或无写入权限，请重选", "儲存目錄不存在或無寫入權限，請重選", "Folder does not exist or is not writable",
            ja: "保存先フォルダが無効または書き込み不可です", ko: "저장 폴더가 없거나 쓰기 권한이 없습니다",
            fr: "Dossier introuvable ou non inscriptible", de: "Ordner existiert nicht oder ist schreibgeschützt",
            es: "La carpeta no existe o no tiene permisos", pt: "A pasta não existe ou sem permissão de escrita",
            ru: "Папка не существует или недоступна для записи"
        )
    }
    public static var autoSaveEnabledNotice: String {
        tr(
            "已开启自动保存", "已開啟自動儲存", "Auto Save enabled",
            ja: "自動保存を有効にしました", ko: "자동 저장 켜짐",
            fr: "Sauvegarde auto activée", de: "Auto-Speichern aktiviert",
            es: "Autoguardado activado", pt: "Salvamento automático ativado",
            ru: "Автосохранение включено"
        )
    }
    public static var autoSaveDisabledNotice: String {
        tr(
            "已关闭自动保存", "已關閉自動儲存", "Auto Save disabled",
            ja: "自動保存を無効にしました", ko: "자동 저장 꺼짐",
            fr: "Sauvegarde auto désactivée", de: "Auto-Speichern deaktiviert",
            es: "Autoguardado desactivado", pt: "Salvamento automático desativado",
            ru: "Автосохранение выключено"
        )
    }
    public static var chosenDirNotWritableNotice: String {
        tr(
            "所选文件夹无写入权限，请更换目录", "所選資料夾無寫入權限，請更換目錄", "Selected folder is not writable",
            ja: "選択したフォルダに書き込み権限がありません", ko: "선택한 폴더에 쓰기 권한이 없습니다",
            fr: "Le dossier choisi n'est pas accessible en écriture", de: "Gewählter Ordner ist nicht beschreibbar",
            es: "La carpeta seleccionada no permite escritura", pt: "A pasta selecionada não permite escrita",
            ru: "Нет прав на запись в выбранную папку"
        )
    }
    public static var saveDirUpdatedNotice: String {
        tr(
            "保存目录已更新", "儲存目錄已更新", "Auto-save folder updated",
            ja: "保存先フォルダを更新しました", ko: "저장 폴더가 업데이트되었습니다",
            fr: "Dossier de sauvegarde mis à jour", de: "Speicherordner aktualisiert",
            es: "Carpeta de guardado actualizada", pt: "Pasta de salvamento atualizada",
            ru: "Папка автосохранения обновлена"
        )
    }
    public static var dirNotFoundNotice: String {
        tr(
            "目录不存在，请重新选择", "目錄不存在，請重新選擇", "Folder not found, please reselect",
            ja: "フォルダが見つかりません", ko: "폴더를 찾을 수 없습니다",
            fr: "Dossier introuvable", de: "Ordner nicht gefunden",
            es: "Carpeta no encontrada", pt: "Pasta não encontrada",
            ru: "Папка не найдена"
        )
    }
    public static var checkUpdateFailedNotice: String {
        tr(
            "检查更新失败", "檢查更新失敗", "Update check failed",
            ja: "アップデートの確認に失敗しました", ko: "업데이트 확인 실패",
            fr: "Échec de la vérification", de: "Update-Prüfung fehlgeschlagen",
            es: "Error al buscar actualizaciones", pt: "Falha ao verificar atualizações",
            ru: "Не удалось проверить обновления"
        )
    }
    public static func alreadyLatestVersionNotice(_ ver: String) -> String {
        tr(
            "当前已是最新版本 (v\(ver))", "目前為最新版本 (v\(ver))", "Up to date (v\(ver))",
            ja: "最新バージョンです (v\(ver))", ko: "최신 버전입니다 (v\(ver))",
            fr: "À jour (v\(ver))", de: "Auf dem neuesten Stand (v\(ver))",
            es: "Ya está actualizado (v\(ver))", pt: "Já está atualizado (v\(ver))",
            ru: "Установлена последняя версия (v\(ver))"
        )
    }
    public static func hotkeyUpdatedNotice(_ hk: String) -> String {
        tr(
            "快捷键已设为 \(hk)", "快捷鍵已設為 \(hk)", "Shortcut set to \(hk)",
            ja: "ショートカットを \(hk) に設定しました", ko: "단축키가 \(hk)(으)로 설정됨",
            fr: "Raccourci défini sur \(hk)", de: "Kurzbefehl auf \(hk) gesetzt",
            es: "Atajo establecido en \(hk)", pt: "Atalho definido para \(hk)",
            ru: "Быстрая клавиша: \(hk)"
        )
    }
    public static func copiedAndAutoSaved(_ w: Int, _ h: Int) -> String {
        tr(
            String(format: "已复制并自动保存 (%d × %d)", w, h),
            String(format: "已複製並自動儲存 (%d × %d)", w, h),
            String(format: "Copied & auto-saved (%d × %d)", w, h),
            ja: String(format: "コピー＆自動保存しました (%d × %d)", w, h),
            ko: String(format: "복사 및 자동 저장됨 (%d × %d)", w, h),
            fr: String(format: "Copié et enregistré (%d × %d)", w, h),
            de: String(format: "Kopiert & gespeichert (%d × %d)", w, h),
            es: String(format: "Copiado y guardado (%d × %d)", w, h),
            pt: String(format: "Copiado e salvo (%d × %d)", w, h),
            ru: String(format: "Скопировано и сохранено (%d × %d)", w, h)
        )
    }
    public static var copiedAndAutoSavedShort: String {
        tr(
            "已复制并自动保存", "已複製並自動儲存", "Copied & auto-saved",
            ja: "コピー＆自動保存しました", ko: "복사 및 자동 저장됨",
            fr: "Copié et enregistré", de: "Kopiert & gespeichert",
            es: "Copiado y guardado", pt: "Copiado e salvo",
            ru: "Скопировано и сохранено"
        )
    }
    public static var autoSavedShort: String {
        tr(
            "已自动保存", "已自動儲存", "Auto-saved",
            ja: "自動保存しました", ko: "자동 저장됨",
            fr: "Enregistré auto", de: "Automatisch gespeichert",
            es: "Autoguardado", pt: "Salvo automaticamente",
            ru: "Автосохранено"
        )
    }
    public static var copiedButAutoSaveFailed: String {
        tr(
            "已复制（目录不可写，已关自动保存）", "已複製（目錄不可寫，已關自動儲存）", "Copied (folder not writable, Auto Save disabled)",
            ja: "コピー済み（保存先書き込み不可のため自動保存オフ）", ko: "복사됨 (폴더 쓰기 불가로 자동 저장 꺼짐)",
            fr: "Copié (dossier non inscriptible, sauvegarde auto désactivée)", de: "Kopiert (Ordner schreibgeschützt, Auto-Speichern aus)",
            es: "Copiado (carpeta sin permisos, autoguardado desactivado)", pt: "Copiado (pasta sem escrita, salvamento auto desativado)",
            ru: "Скопировано (папка недоступна, автосохранение выкл.)"
        )
    }
    public static var dirNotWritableAutoSaveDisabled: String {
        tr(
            "目录不可写，已关闭自动保存", "目錄不可寫，已關閉自動儲存", "Folder not writable, Auto Save disabled",
            ja: "保存先に書き込めないため自動保存を無効化", ko: "폴더 쓰기 불가, 자동 저장 해제됨",
            fr: "Dossier non inscriptible, sauvegarde auto désactivée", de: "Ordner schreibgeschützt, Auto-Speichern deaktiviert",
            es: "Carpeta sin permisos, autoguardado desactivado", pt: "Pasta sem escrita, salvamento auto desativado",
            ru: "Папка недоступна, автосохранение выключено"
        )
    }
    public static func copiedToClipboardSize(_ w: Int, _ h: Int) -> String {
        tr(
            String(format: "已复制到剪贴板 (%d × %d)", w, h),
            String(format: "已複製到剪貼簿 (%d × %d)", w, h),
            String(format: "Copied to clipboard (%d × %d)", w, h),
            ja: String(format: "クリップボードにコピー (%d × %d)", w, h),
            ko: String(format: "클립보드에 복사됨 (%d × %d)", w, h),
            fr: String(format: "Copié dans le presse-papiers (%d × %d)", w, h),
            de: String(format: "In Zwischenablage kopiert (%d × %d)", w, h),
            es: String(format: "Copiado al portapapeles (%d × %d)", w, h),
            pt: String(format: "Copiado para a área de transferência (%d × %d)", w, h),
            ru: String(format: "Скопировано в буфер (%d × %d)", w, h)
        )
    }
    public static var copiedToClipboardShort: String {
        tr(
            "已复制到剪贴板", "已複製到剪貼簿", "Copied to clipboard",
            ja: "クリップボードにコピーしました", ko: "클립보드에 복사됨",
            fr: "Copié dans le presse-papiers", de: "In Zwischenablage kopiert",
            es: "Copiado al portapapeles", pt: "Copiado para a área de transferência",
            ru: "Скопировано в буфер обмена"
        )
    }
    public static var savedShort: String {
        tr(
            "已保存", "已儲存", "Saved",
            ja: "保存しました", ko: "저장됨",
            fr: "Enregistré", de: "Gespeichert",
            es: "Guardado", pt: "Salvo",
            ru: "Сохранено"
        )
    }

    public static var permissionPromptDialogNotice: String {
        tr(
            "请在系统弹窗中点击允许（授权后再次点击即可截图）",
            "請在系統彈窗中點擊允許（授權後再次點擊即可截圖）",
            "Please click Allow in the system dialog, then try again",
            ja: "システムダイアログで「許可」をクリックしてください",
            ko: "시스템 대화상자에서 '허용'을 클릭한 후 다시 시도하세요",
            fr: "Veuillez cliquer sur Autoriser dans la boîte système",
            de: "Bitte im Systemdialog auf „Erlauben“ klicken",
            es: "Haga clic en Permitir en el diálogo del sistema",
            pt: "Clique em Permitir na caixa do sistema e tente novamente",
            ru: "Нажмите «Разрешить» в системном окне и повторите"
        )
    }
    public static var permissionDeniedSettingsNotice: String {
        tr(
            "请先在系统设置中开启 SpanShot 的屏幕录制权限",
            "請先在系統設定中開啟 SpanShot 的螢幕錄製權限",
            "Please grant Screen Recording permission in System Settings",
            ja: "システム設定で画面収録の権限を許可してください",
            ko: "시스템 설정에서 화면 기록 권한을 허용해 주세요",
            fr: "Veuillez accorder l'accès Enregistrement de l'écran",
            de: "Bitte Bildschirmaufnahme in den Systemeinstellungen erlauben",
            es: "Conceda permiso de Grabación de pantalla en Ajustes",
            pt: "Conceda permissão de Gravação de Tela nos Ajustes",
            ru: "Разрешите запись экрана в Системных настройках"
        )
    }

    // MARK: - Status Bar & App Menu
    public static func statusTooltip(_ hk: String) -> String {
        tr(
            "SpanShot — 跨屏横纵长截图 (\(hk))",
            "SpanShot — 跨螢幕橫縱長截圖 (\(hk))",
            "SpanShot — Cross-Screen & Scrolling Capture (\(hk))",
            ja: "SpanShot — スクロール＆マルチ画面キャプチャ (\(hk))",
            ko: "SpanShot — 스크롤 및 다중 모니터 캡처 (\(hk))",
            fr: "SpanShot — Capture défilante & multi-écrans (\(hk))",
            de: "SpanShot — Scroll- & Multi-Monitor-Aufnahme (\(hk))",
            es: "SpanShot — Captura desplazable y multipantalla (\(hk))",
            pt: "SpanShot — Captura rolante e multitelas (\(hk))",
            ru: "SpanShot — Длинные и многоэкранные снимки (\(hk))"
        )
    }
    public static func menuStartCapture(_ hk: String) -> String {
        "\(startCapture) (\(hk))"
    }
    public static var menuVerticalScroll: String {
        tr(
            "纵向长截图...", "縱向長截圖...", "Vertical Scroll Capture...",
            ja: "縦スクロールキャプチャ...", ko: "세로 스크롤 캡처...",
            fr: "Capture défilante verticale...", de: "Vertikale Scroll-Aufnahme...",
            es: "Captura con desplazamiento vertical...", pt: "Captura de rolagem vertical...",
            ru: "Вертикальный длинный снимок..."
        )
    }
    public static var menuHorizontalScroll: String {
        tr(
            "横向长截图...", "橫向長截圖...", "Horizontal Scroll Capture...",
            ja: "横スクロールキャプチャ...", ko: "가로 스크롤 캡처...",
            fr: "Capture défilante horizontale...", de: "Horizontale Scroll-Aufnahme...",
            es: "Captura con desplazamiento horizontal...", pt: "Captura de rolagem horizontal...",
            ru: "Горизонтальный длинный снимок..."
        )
    }
    public static var menuWindowShadow: String { windowShadowLabel }
    public static var menuQuickCopy: String {
        tr(
            "快捷截图（只复制不弹窗）", "快捷截圖（只複製不彈窗）", "Quick Copy (No Preview)",
            ja: "クイックコピー（プレビューなし）", ko: "빠른 복사 (미리보기 없음)",
            fr: "Copie rapide (sans aperçu)", de: "Schnellkopie (ohne Vorschau)",
            es: "Copia rápida (sin vista previa)", pt: "Cópia rápida (sem prévia)",
            ru: "Быстрое копирование (без окна)"
        )
    }
    public static var menuAutoSave: String { autoSaveLabel }
    public static var menuPickAutoSaveDir: String {
        tr(
            "选择自动保存目录...", "選擇自動儲存目錄...", "Select Auto-Save Folder...",
            ja: "自動保存フォルダを選択...", ko: "자동 저장 폴더 선택...",
            fr: "Choisir le dossier de sauvegarde...", de: "Auto-Speicherordner wählen...",
            es: "Seleccionar carpeta de autoguardado...", pt: "Selecionar pasta de salvamento...",
            ru: "Выбрать папку автосохранения..."
        )
    }
    public static var menuKeepAlive: String { keepAliveLabel }
    public static var menuHideStatusBar: String { hideStatusBarLabel }
    public static var menuAutoStart: String { autoStartLabel }
    public static var menuLanguage: String {
        tr(
            "语言 / Language", "語言 / Language", "Language",
            ja: "言語 / Language", ko: "언어 / Language",
            fr: "Langue / Language", de: "Sprache / Language",
            es: "Idioma / Language", pt: "Idioma / Language",
            ru: "Язык / Language"
        )
    }
    public static var menuCheckUpdate: String { "\(checkUpdate)..." }
    public static var menuShowMain: String {
        tr(
            "显示主窗口", "顯示主視窗", "Show Main Window",
            ja: "メインウィンドウを表示", ko: "메인 창 표시",
            fr: "Afficher la fenêtre principale", de: "Hauptfenster anzeigen",
            es: "Mostrar ventana principal", pt: "Mostrar janela principal",
            ru: "Показать главное окно"
        )
    }
    public static var menuQuitApp: String {
        tr(
            "彻底退出 SpanShot", "徹底退出 SpanShot", "Quit SpanShot",
            ja: "SpanShot を終了", ko: "SpanShot 종료",
            fr: "Quitter SpanShot", de: "SpanShot beenden",
            es: "Salir de SpanShot", pt: "Sair do SpanShot",
            ru: "Выйти из SpanShot"
        )
    }

    // MARK: - RegionSelectorForm
    public static var promptVerticalScroll: String {
        tr(
            "纵向长截图 · 请拖动框选区域或点击窗口 (Esc 退出)",
            "縱向長截圖 · 請拖動框選區域或點選視窗 (Esc 退出)",
            "Vertical Scroll · Drag region or click window (Esc to cancel)",
            ja: "縦スクロール · 範囲をドラッグまたはウィンドウをクリック (Escで終了)",
            ko: "세로 스크롤 · 영역을 드래그하거나 창을 클릭하세요 (Esc 취소)",
            fr: "Défilement vertical · Glissez ou cliquez sur une fenêtre (Échap pour annuler)",
            de: "Vertikales Scrollen · Bereich ziehen oder Fenster klicken (Esc zum Abbrechen)",
            es: "Desplazamiento vertical · Arrastre o haga clic en ventana (Esc para cancelar)",
            pt: "Rolagem vertical · Arraste ou clique na janela (Esc para cancelar)",
            ru: "Вертикальная прокрутка · Выделите область или кликните окно (Esc — отмена)"
        )
    }
    public static var promptHorizontalScroll: String {
        tr(
            "横向长截图 · 请拖动框选区域或点击窗口 (Esc 退出)",
            "橫向長截圖 · 請拖動框選區域或點選視窗 (Esc 退出)",
            "Horizontal Scroll · Drag region or click window (Esc to cancel)",
            ja: "横スクロール · 範囲をドラッグまたはウィンドウをクリック (Escで終了)",
            ko: "가로 스크롤 · 영역을 드래그하거나 창을 클릭하세요 (Esc 취소)",
            fr: "Défilement horizontal · Glissez ou cliquez sur une fenêtre (Échap pour annuler)",
            de: "Horizontales Scrollen · Bereich ziehen oder Fenster klicken (Esc zum Abbrechen)",
            es: "Desplazamiento horizontal · Arrastre o haga clic en ventana (Esc para cancelar)",
            pt: "Rolagem horizontal · Arraste ou clique na janela (Esc para cancelar)",
            ru: "Горизонтальная прокрутка · Выделите область или кликните окно (Esc — отмена)"
        )
    }
    public static var promptNormalCapture: String {
        tr(
            "请拖动框选区域或点击窗口 · 右键或 Esc 退出",
            "請拖動框選區域或點選視窗 · 右鍵或 Esc 退出",
            "Drag to select region or click a window · Right-click or Esc to cancel",
            ja: "範囲をドラッグまたはウィンドウをクリック · 右クリック/Escで終了",
            ko: "영역을 드래그하거나 창을 클릭 · 우클릭 또는 Esc로 취소",
            fr: "Glissez pour sélectionner ou cliquez une fenêtre · Clic droit ou Échap",
            de: "Bereich ziehen oder Fenster klicken · Rechtsklick oder Esc zum Abbrechen",
            es: "Arrastre para seleccionar o clic en ventana · Clic derecho o Esc",
            pt: "Arraste para selecionar ou clique na janela · Clique direito ou Esc",
            ru: "Выделите область или кликните окно · ПКМ или Esc для отмены"
        )
    }
    public static func sizeBadgeWithWindowShadow(_ w: Int, _ h: Int) -> String {
        tr(
            String(format: "%d × %d px · 圆角阴影", w, h),
            String(format: "%d × %d px · 圓角陰影", w, h),
            String(format: "%d × %d px · Window Shadow", w, h),
            ja: String(format: "%d × %d px · 角丸と影", w, h),
            ko: String(format: "%d × %d px · 창 그림자", w, h),
            fr: String(format: "%d × %d px · Ombre", w, h),
            de: String(format: "%d × %d px · Schatten", w, h),
            es: String(format: "%d × %d px · Sombra", w, h),
            pt: String(format: "%d × %d px · Sombra", w, h),
            ru: String(format: "%d × %d px · С тенью", w, h)
        )
    }
    public static var toolbarVerticalScrollBtn: String {
        tr(
            "纵向长截", "縱向長截", "V-Scroll",
            ja: "縦長撮影", ko: "세로 캡처",
            fr: "Défil. V", de: "V-Scroll",
            es: "Desp. V", pt: "Rolag. V",
            ru: "Верт."
        )
    }
    public static var toolbarHorizontalScrollBtn: String {
        tr(
            "横向长截", "橫向長截", "H-Scroll",
            ja: "横長撮影", ko: "가로 캡처",
            fr: "Défil. H", de: "H-Scroll",
            es: "Desp. H", pt: "Rolag. H",
            ru: "Гориз."
        )
    }
    public static var tipRectTool: String {
        tr("矩形", "矩形", "Rectangle", ja: "四角形", ko: "사각형", fr: "Rectangle", de: "Rechteck", es: "Rectángulo", pt: "Retângulo", ru: "Прямоугольник")
    }
    public static var tipArrowTool: String {
        tr("箭头", "箭頭", "Arrow", ja: "矢印", ko: "화살표", fr: "Flèche", de: "Pfeil", es: "Flecha", pt: "Seta", ru: "Стрелка")
    }
    public static var tipPenTool: String {
        tr("画笔", "畫筆", "Pen", ja: "ペン", ko: "펜", fr: "Stylo", de: "Stift", es: "Lápiz", pt: "Caneta", ru: "Перо")
    }
    public static var tipVerticalScroll: String {
        tr("纵向长截图 (V)", "縱向長截圖 (V)", "Vertical Scroll (V)", ja: "縦スクロール (V)", ko: "세로 스크롤 (V)", fr: "Défilement vertical (V)", de: "Vertikal scrollen (V)", es: "Desplazamiento vertical (V)", pt: "Rolagem vertical (V)", ru: "Вертикальный снимок (V)")
    }
    public static var tipHorizontalScroll: String {
        tr("横向长截图 (H)", "橫向長截圖 (H)", "Horizontal Scroll (H)", ja: "横スクロール (H)", ko: "가로 스크롤 (H)", fr: "Défilement horizontal (H)", de: "Horizontal scrollen (H)", es: "Desplazamiento horizontal (H)", pt: "Rolagem horizontal (H)", ru: "Горизонтальный снимок (H)")
    }
    public static var tipUndo: String {
        tr("撤销 (⌘Z)", "復原 (⌘Z)", "Undo (⌘Z)", ja: "元に戻す (⌘Z)", ko: "실행 취소 (⌘Z)", fr: "Annuler (⌘Z)", de: "Rückgängig (⌘Z)", es: "Deshacer (⌘Z)", pt: "Desfazer (⌘Z)", ru: "Отменить (⌘Z)")
    }
    public static var tipPin: String {
        tr("贴图 (P)", "釘選貼圖 (P)", "Pin to Screen (P)", ja: "ピン留め (P)", ko: "화면 고정 (P)", fr: "Épingler (P)", de: "Anheften (P)", es: "Fijar (P)", pt: "Fixar (P)", ru: "Закрепить (P)")
    }
    public static var tipSave: String {
        tr("保存 (⌘S)", "儲存 (⌘S)", "Save (⌘S)", ja: "保存 (⌘S)", ko: "저장 (⌘S)", fr: "Enregistrer (⌘S)", de: "Speichern (⌘S)", es: "Guardar (⌘S)", pt: "Salvar (⌘S)", ru: "Сохранить (⌘S)")
    }
    public static var tipCancel: String {
        tr("退出 (Esc)", "退出 (Esc)", "Cancel (Esc)", ja: "キャンセル (Esc)", ko: "취소 (Esc)", fr: "Annuler (Échap)", de: "Abbrechen (Esc)", es: "Cancelar (Esc)", pt: "Cancelar (Esc)", ru: "Отмена (Esc)")
    }
    public static var tipFinish: String {
        tr("完成 (↩)", "完成 (↩)", "Done (↩)", ja: "完了 (↩)", ko: "완료 (↩)", fr: "Terminer (↩)", de: "Fertig (↩)", es: "Listo (↩)", pt: "Concluir (↩)", ru: "Готово (↩)")
    }

    // MARK: - ScrollCaptureSessionForm
    public static var titleVerticalScroll: String {
        tr("纵向长截图", "縱向長截圖", "Vertical Scroll", ja: "縦スクロール", ko: "세로 스크롤", fr: "Défilement V", de: "Vertikal-Scroll", es: "Desplazamiento V", pt: "Rolagem V", ru: "Верт. снимок")
    }
    public static var titleHorizontalScroll: String {
        tr("横向长截图", "橫向長截圖", "Horizontal Scroll", ja: "横スクロール", ko: "가로 스크롤", fr: "Défilement H", de: "Horizontal-Scroll", es: "Desplazamiento H", pt: "Rolagem H", ru: "Гориз. снимок")
    }
    public static var titleNormalShot: String {
        tr("截图", "截圖", "Screenshot", ja: "スクリーンショット", ko: "스크린샷", fr: "Capture", de: "Aufnahme", es: "Captura", pt: "Captura", ru: "Снимок")
    }
    public static var btnPauseScroll: String {
        tr("暂停", "暫停", "Pause", ja: "一時停止", ko: "일시정지", fr: "Pause", de: "Pause", es: "Pausar", pt: "Pausar", ru: "Пауза")
    }
    public static var btnAutoScroll: String {
        tr("自动滚动", "自動捲動", "Auto Scroll", ja: "自動スクロール", ko: "자동 스크롤", fr: "Défil. auto", de: "Auto-Scroll", es: "Auto-despl.", pt: "Auto-rolagem", ru: "Автоскролл")
    }
    public static var btnDone: String {
        tr("完成", "完成", "Done", ja: "完了", ko: "완료", fr: "OK", de: "Fertig", es: "Listo", pt: "OK", ru: "Готово")
    }

    // MARK: - ResultPreviewForm
    public static var previewPan: String {
        tr("浏览", "瀏覽", "Pan", ja: "移動", ko: "이동", fr: "Main", de: "Bewegen", es: "Mover", pt: "Mover", ru: "Обзор")
    }
    public static var previewRect: String {
        tr("方框", "方框", "Rect", ja: "四角", ko: "사각형", fr: "Cadre", de: "Rechteck", es: "Cuadro", pt: "Retâng.", ru: "Рамка")
    }
    public static var previewArrow: String {
        tr("箭头", "箭頭", "Arrow", ja: "矢印", ko: "화살표", fr: "Flèche", de: "Pfeil", es: "Flecha", pt: "Seta", ru: "Стрелка")
    }
    public static var previewPen: String {
        tr("画笔", "畫筆", "Pen", ja: "ペン", ko: "펜", fr: "Stylo", de: "Stift", es: "Lápiz", pt: "Caneta", ru: "Перо")
    }
    public static var previewCrop: String {
        tr("裁剪", "裁剪", "Crop", ja: "切り抜き", ko: "자르기", fr: "Rogner", de: "Zuschnitt", es: "Recortar", pt: "Cortar", ru: "Обрезка")
    }
    public static var previewUndo: String {
        tr("撤销", "復原", "Undo", ja: "戻す", ko: "취소", fr: "Annuler", de: "Zurück", es: "Deshacer", pt: "Desfazer", ru: "Отмена")
    }
    public static var previewFitWindow: String {
        tr("适应窗口", "適應視窗", "Fit", ja: "全体表示", ko: "창 맞춤", fr: "Ajuster", de: "Anpassen", es: "Ajustar", pt: "Ajustar", ru: "Вписать")
    }
    public static var previewPin: String {
        tr("钉选", "釘選", "Pin", ja: "ピン", ko: "고정", fr: "Épingler", de: "Pin", es: "Fijar", pt: "Fixar", ru: "Пин")
    }
    public static var previewSave: String {
        tr("下载", "儲存", "Save", ja: "保存", ko: "저장", fr: "Sauver", de: "Speichern", es: "Guardar", pt: "Salvar", ru: "Сохр.")
    }
    public static var previewFinish: String {
        tr("完成", "完成", "Done", ja: "完了", ko: "완료", fr: "Terminer", de: "Fertig", es: "Listo", pt: "Concluir", ru: "Готово")
    }

    // MARK: - PinWindowForm
    public static var pinCopyImage: String {
        tr("复制图像 (⌘C)", "複製影像 (⌘C)", "Copy Image (⌘C)", ja: "画像をコピー (⌘C)", ko: "이미지 복사 (⌘C)", fr: "Copier l'image (⌘C)", de: "Bild kopieren (⌘C)", es: "Copiar imagen (⌘C)", pt: "Copiar imagem (⌘C)", ru: "Копировать (⌘C)")
    }
    public static var pinResetSize: String {
        tr("还原 100% 尺寸", "還原 100% 尺寸", "Actual Size (100%)", ja: "100% サイズに戻す", ko: "원래 크기 (100%)", fr: "Taille réelle (100%)", de: "Originalgröße (100%)", es: "Tamaño real (100%)", pt: "Tamanho real (100%)", ru: "Масштаб 100%")
    }
    public static var pinClose: String {
        tr("关闭贴图 (Esc / 双击)", "關閉貼圖 (Esc / 雙擊)", "Close Pin (Esc / Double-click)", ja: "閉じる (Esc / ダブルクリック)", ko: "닫기 (Esc / 더블클릭)", fr: "Fermer (Échap / Double-clic)", de: "Schließen (Esc / Doppelklick)", es: "Cerrar (Esc / Doble clic)", pt: "Fechar (Esc / Duplo clique)", ru: "Закрыть (Esc / Двойной клик)")
    }

    // MARK: - Folder Picker Dialog
    public static var folderPickerTitle: String {
        tr("选择截图自动保存目录", "選擇截圖自動儲存目錄", "Select Auto-Save Folder", ja: "自動保存フォルダの選択", ko: "자동 저장 폴더 선택", fr: "Choisir le dossier de sauvegarde", de: "Auto-Speicherordner wählen", es: "Seleccionar carpeta de autoguardado", pt: "Selecionar pasta de salvamento", ru: "Выбор папки автосохранения")
    }
    public static var folderPickerMessage: String {
        tr(
            "请选择用于自动保存 SpanShot 截图的文件夹（需具备写入权限）",
            "請選擇用於自動儲存 SpanShot 截圖的資料夾（需具備寫入權限）",
            "Choose a writable folder to automatically save SpanShot screenshots",
            ja: "SpanShot のスクリーンショットを自動保存するフォルダを選択してください",
            ko: "SpanShot 스크린샷을 자동 저장할 폴더를 선택하세요",
            fr: "Choisissez un dossier accessible en écriture pour sauvegarder les captures",
            de: "Wählen Sie einen beschreibbaren Ordner zum automatischen Speichern",
            es: "Elija una carpeta con permisos de escritura para guardar las capturas",
            pt: "Escolha uma pasta com permissão de escrita para salvar as capturas",
            ru: "Выберите папку с правами записи для автоматического сохранения снимков"
        )
    }
    public static var folderPickerPrompt: String {
        tr("选择文件夹", "選擇資料夾", "Choose Folder", ja: "選択", ko: "선택", fr: "Choisir", de: "Auswählen", es: "Seleccionar", pt: "Escolher", ru: "Выбрать")
    }
}
