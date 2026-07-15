import Foundation

/// Simple, code-embedded localization. Picks strings by system language and
/// falls back to English for unknown languages. (Works with the manual .app
/// packaging — no .lproj / resource bundle required.)
public struct L10n {
    public let working: String     // menu row: working
    public let asking: String      // menu row: asking a question / waiting
    public let done: String        // menu row: done
    public let noSessions: String  // header: no active sessions
    public let waitingWord: String // summary counter: "2 <waiting>"
    public let workingWord: String // summary counter: "1 <working>"
    public let doneWord: String    // summary counter: "1 <done>"
    public let refresh: String     // menu: refresh
    public let quit: String        // menu: quit
    public let notifyTitle: String // notification title: on turning red
    public let notifyMenu: String  // menu: notifications (toggle)
    public let desktopAppMissing: String // feedback: claude:// has no handler (desktop app not installed)
    public let activeSessions: String // menu header title (when there are sessions)
    public let hint: String        // menu footer hint (how to open a session)
    public let checkUpdates: String       // menu: manual update check
    public let upToDate: String           // update check: already on the latest version
    public let updateCheckFailed: String  // update check: network/API problem
    public let localeID: String    // for the relative-time formatter (e.g. "58s ago")

    /// Menu label for a given state.
    public func label(for state: State) -> String {
        switch state {
        case .red:    return asking
        case .yellow: return working
        case .green:  return done
        }
    }

    /// Localization for the active language. macOS 12+ compatible (reads the
    /// language code from `preferredLanguages`).
    public static var current: L10n {
        let pref = Locale.preferredLanguages.first ?? "en"
        let code = String(pref.prefix(2)).lowercased()
        return tables[code] ?? english
    }

    // MARK: - Languages

    public static let english = L10n(
        working: "Working…", asking: "Asking a question", done: "Done",
        noSessions: "No active Claude sessions",
        waitingWord: "waiting", workingWord: "working", doneWord: "done",
        refresh: "Refresh", quit: "Quit",
        notifyTitle: "Claude is waiting for you", notifyMenu: "Notifications",
        desktopAppMissing: "Claude desktop app is not installed — cannot open this session",
        activeSessions: "Active sessions", hint: "Click a session to jump to it",
        checkUpdates: "Check for Updates…", upToDate: "You're up to date",
        updateCheckFailed: "Could not check for updates",
        localeID: "en")

    public static let tables: [String: L10n] = [
        "en": english,
        "tr": L10n(
            working: "Çalışıyor…", asking: "Soru soruyor", done: "Bitti",
            noSessions: "Aktif Claude oturumu yok",
            waitingWord: "bekliyor", workingWord: "çalışıyor", doneWord: "bitti",
            refresh: "Yenile", quit: "Çıkış",
            notifyTitle: "Claude seni bekliyor", notifyMenu: "Bildirimler",
            desktopAppMissing: "Claude masaüstü uygulaması yüklü değil — bu oturum açılamıyor",
            activeSessions: "Aktif oturumlar", hint: "Gitmek için bir oturuma tıkla",
            checkUpdates: "Güncellemeleri Denetle…", upToDate: "Uygulama güncel",
        updateCheckFailed: "Güncellemeler denetlenemedi",
        localeID: "tr"),
        "es": L10n(
            working: "Trabajando…", asking: "Haciendo una pregunta", done: "Terminado",
            noSessions: "No hay sesiones de Claude activas",
            waitingWord: "esperando", workingWord: "trabajando", doneWord: "terminado",
            refresh: "Actualizar", quit: "Salir",
            notifyTitle: "Claude te está esperando", notifyMenu: "Notificaciones",
            desktopAppMissing: "La app de escritorio de Claude no está instalada — no se puede abrir esta sesión",
            activeSessions: "Sesiones activas", hint: "Haz clic en una sesión para abrirla",
            checkUpdates: "Buscar actualizaciones…", upToDate: "Estás al día",
        updateCheckFailed: "No se pudo buscar actualizaciones",
        localeID: "es"),
        "de": L10n(
            working: "Arbeitet…", asking: "Stellt eine Frage", done: "Fertig",
            noSessions: "Keine aktiven Claude-Sitzungen",
            waitingWord: "wartend", workingWord: "arbeitend", doneWord: "fertig",
            refresh: "Aktualisieren", quit: "Beenden",
            notifyTitle: "Claude wartet auf dich", notifyMenu: "Benachrichtigungen",
            desktopAppMissing: "Die Claude-Desktop-App ist nicht installiert — Sitzung kann nicht geöffnet werden",
            activeSessions: "Aktive Sitzungen", hint: "Sitzung anklicken, um zu ihr zu springen",
            checkUpdates: "Nach Updates suchen…", upToDate: "Du bist auf dem neuesten Stand",
        updateCheckFailed: "Updates konnten nicht geprüft werden",
        localeID: "de"),
        "fr": L10n(
            working: "En cours…", asking: "Pose une question", done: "Terminé",
            noSessions: "Aucune session Claude active",
            waitingWord: "en attente", workingWord: "en cours", doneWord: "terminé",
            refresh: "Actualiser", quit: "Quitter",
            notifyTitle: "Claude vous attend", notifyMenu: "Notifications",
            desktopAppMissing: "L'application de bureau Claude n'est pas installée — impossible d'ouvrir cette session",
            activeSessions: "Sessions actives", hint: "Cliquez sur une session pour y accéder",
            checkUpdates: "Rechercher des mises à jour…", upToDate: "Vous êtes à jour",
        updateCheckFailed: "Impossible de vérifier les mises à jour",
        localeID: "fr"),
        "it": L10n(
            working: "In corso…", asking: "Fa una domanda", done: "Completato",
            noSessions: "Nessuna sessione Claude attiva",
            waitingWord: "in attesa", workingWord: "in corso", doneWord: "completato",
            refresh: "Aggiorna", quit: "Esci",
            notifyTitle: "Claude ti sta aspettando", notifyMenu: "Notifiche",
            desktopAppMissing: "L'app desktop di Claude non è installata — impossibile aprire questa sessione",
            activeSessions: "Sessioni attive", hint: "Clicca una sessione per aprirla",
            checkUpdates: "Controlla aggiornamenti…", upToDate: "Sei aggiornato",
        updateCheckFailed: "Impossibile controllare gli aggiornamenti",
        localeID: "it"),
        "pt": L10n(
            working: "Trabalhando…", asking: "Fazendo uma pergunta", done: "Concluído",
            noSessions: "Nenhuma sessão do Claude ativa",
            waitingWord: "aguardando", workingWord: "trabalhando", doneWord: "concluído",
            refresh: "Atualizar", quit: "Sair",
            notifyTitle: "Claude está esperando por você", notifyMenu: "Notificações",
            desktopAppMissing: "O app desktop do Claude não está instalado — não é possível abrir esta sessão",
            activeSessions: "Sessões ativas", hint: "Clique em uma sessão para abri-la",
            checkUpdates: "Buscar atualizações…", upToDate: "Você está atualizado",
        updateCheckFailed: "Não foi possível buscar atualizações",
        localeID: "pt"),
        "ru": L10n(
            working: "Работает…", asking: "Задаёт вопрос", done: "Готово",
            noSessions: "Нет активных сессий Claude",
            waitingWord: "ждут", workingWord: "работают", doneWord: "готово",
            refresh: "Обновить", quit: "Выход",
            notifyTitle: "Claude ждёт вас", notifyMenu: "Уведомления",
            desktopAppMissing: "Приложение Claude для компьютера не установлено — не удаётся открыть эту сессию",
            activeSessions: "Активные сессии", hint: "Нажмите на сессию, чтобы открыть",
            checkUpdates: "Проверить обновления…", upToDate: "У вас последняя версия",
        updateCheckFailed: "Не удалось проверить обновления",
        localeID: "ru"),
        "ja": L10n(
            working: "作業中…", asking: "質問中", done: "完了",
            noSessions: "アクティブな Claude セッションはありません",
            waitingWord: "待機中", workingWord: "作業中", doneWord: "完了",
            refresh: "更新", quit: "終了",
            notifyTitle: "Claude が待っています", notifyMenu: "通知",
            desktopAppMissing: "Claude デスクトップアプリが未インストールのため、このセッションを開けません",
            activeSessions: "アクティブなセッション", hint: "セッションをクリックして開く",
            checkUpdates: "アップデートを確認…", upToDate: "最新バージョンです",
        updateCheckFailed: "アップデートを確認できませんでした",
        localeID: "ja"),
        "zh": L10n(
            working: "工作中…", asking: "正在提问", done: "完成",
            noSessions: "没有活动的 Claude 会话",
            waitingWord: "等待中", workingWord: "工作中", doneWord: "完成",
            refresh: "刷新", quit: "退出",
            notifyTitle: "Claude 正在等你", notifyMenu: "通知",
            desktopAppMissing: "未安装 Claude 桌面应用 — 无法打开此会话",
            activeSessions: "活动会话", hint: "点击会话以跳转",
            checkUpdates: "检查更新…", upToDate: "已是最新版本",
        updateCheckFailed: "无法检查更新",
        localeID: "zh"),
        "ko": L10n(
            working: "작업 중…", asking: "질문 중", done: "완료",
            noSessions: "활성 Claude 세션 없음",
            waitingWord: "대기 중", workingWord: "작업 중", doneWord: "완료",
            refresh: "새로고침", quit: "종료",
            notifyTitle: "Claude가 기다리고 있습니다", notifyMenu: "알림",
            desktopAppMissing: "Claude 데스크톱 앱이 설치되어 있지 않아 이 세션을 열 수 없습니다",
            activeSessions: "활성 세션", hint: "세션을 클릭하여 이동",
            checkUpdates: "업데이트 확인…", upToDate: "최신 버전입니다",
        updateCheckFailed: "업데이트를 확인할 수 없습니다",
        localeID: "ko"),
    ]
}
