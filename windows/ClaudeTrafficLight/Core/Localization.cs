using System.Globalization;

namespace ClaudeTrafficLight.Core;

/// <summary>
/// Simple, code-embedded localization. Picks strings by system language and
/// falls back to English for unknown languages. Mirrors the macOS L10n tables.
/// </summary>
public sealed record L10n(
    string Working,        // menu row: working
    string Asking,         // menu row: asking a question / waiting
    string Done,           // menu row: done
    string NoSessions,     // header: no active sessions
    string WaitingWord,    // summary counter: "2 <waiting>"
    string WorkingWord,    // summary counter: "1 <working>"
    string DoneWord,       // summary counter: "1 <done>"
    string Refresh,        // menu: refresh
    string Quit,           // menu: quit
    string NotifyTitle,    // notification title: on turning red
    string NotifyMenu,     // menu: notifications (toggle)
    string ActiveSessions, // menu header title (when there are sessions)
    string Hint,           // menu footer hint
    string CheckUpdates,   // menu: manual update check
    string UpToDate,       // update check: already on the latest version
    string UpdateCheckFailed, // update check: network/API problem
    string LocaleId)
{
    /// <summary>Menu label for a given state.</summary>
    public string Label(State state) => state switch
    {
        State.Red => Asking,
        State.Yellow => Working,
        State.Green => Done,
        _ => Done
    };

    /// <summary>Localization for the active UI language (first two letters).</summary>
    public static L10n Current
    {
        get
        {
            string code;
            try { code = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName.ToLowerInvariant(); }
            catch { code = "en"; }
            return Tables.TryGetValue(code, out var l) ? l : English;
        }
    }

    public static readonly L10n English = new(
        "Working…", "Asking a question", "Done",
        "No active Claude sessions",
        "waiting", "working", "done",
        "Refresh", "Quit",
        "Claude is waiting for you", "Notifications",
        "Active sessions", "Click a session to jump to it", "Check for Updates…", "You're up to date",
            "Could not check for updates", "en");

    public static readonly Dictionary<string, L10n> Tables = new()
    {
        ["en"] = English,
        ["tr"] = new(
            "Çalışıyor…", "Soru soruyor", "Bitti",
            "Aktif Claude oturumu yok",
            "bekliyor", "çalışıyor", "bitti",
            "Yenile", "Çıkış",
            "Claude seni bekliyor", "Bildirimler",
            "Aktif oturumlar", "Gitmek için bir oturuma tıkla", "Güncellemeleri Denetle…", "Uygulama güncel",
            "Güncellemeler denetlenemedi", "tr"),
        ["es"] = new(
            "Trabajando…", "Haciendo una pregunta", "Terminado",
            "No hay sesiones de Claude activas",
            "esperando", "trabajando", "terminado",
            "Actualizar", "Salir",
            "Claude te está esperando", "Notificaciones",
            "Sesiones activas", "Haz clic en una sesión para abrirla", "Buscar actualizaciones…", "Estás al día",
            "No se pudo buscar actualizaciones", "es"),
        ["de"] = new(
            "Arbeitet…", "Stellt eine Frage", "Fertig",
            "Keine aktiven Claude-Sitzungen",
            "wartend", "arbeitend", "fertig",
            "Aktualisieren", "Beenden",
            "Claude wartet auf dich", "Benachrichtigungen",
            "Aktive Sitzungen", "Sitzung anklicken, um zu ihr zu springen", "Nach Updates suchen…", "Du bist auf dem neuesten Stand",
            "Updates konnten nicht geprüft werden", "de"),
        ["fr"] = new(
            "En cours…", "Pose une question", "Terminé",
            "Aucune session Claude active",
            "en attente", "en cours", "terminé",
            "Actualiser", "Quitter",
            "Claude vous attend", "Notifications",
            "Sessions actives", "Cliquez sur une session pour y accéder", "Rechercher des mises à jour…", "Vous êtes à jour",
            "Impossible de vérifier les mises à jour", "fr"),
        ["it"] = new(
            "In corso…", "Fa una domanda", "Completato",
            "Nessuna sessione Claude attiva",
            "in attesa", "in corso", "completato",
            "Aggiorna", "Esci",
            "Claude ti sta aspettando", "Notifiche",
            "Sessioni attive", "Clicca una sessione per aprirla", "Controlla aggiornamenti…", "Sei aggiornato",
            "Impossibile controllare gli aggiornamenti", "it"),
        ["pt"] = new(
            "Trabalhando…", "Fazendo uma pergunta", "Concluído",
            "Nenhuma sessão do Claude ativa",
            "aguardando", "trabalhando", "concluído",
            "Atualizar", "Sair",
            "Claude está esperando por você", "Notificações",
            "Sessões ativas", "Clique em uma sessão para abri-la", "Buscar atualizações…", "Você está atualizado",
            "Não foi possível buscar atualizações", "pt"),
        ["ru"] = new(
            "Работает…", "Задаёт вопрос", "Готово",
            "Нет активных сессий Claude",
            "ждут", "работают", "готово",
            "Обновить", "Выход",
            "Claude ждёт вас", "Уведомления",
            "Активные сессии", "Нажмите на сессию, чтобы открыть", "Проверить обновления…", "У вас последняя версия",
            "Не удалось проверить обновления", "ru"),
        ["ja"] = new(
            "作業中…", "質問中", "完了",
            "アクティブな Claude セッションはありません",
            "待機中", "作業中", "完了",
            "更新", "終了",
            "Claude が待っています", "通知",
            "アクティブなセッション", "セッションをクリックして開く", "アップデートを確認…", "最新バージョンです",
            "アップデートを確認できませんでした", "ja"),
        ["zh"] = new(
            "工作中…", "正在提问", "完成",
            "没有活动的 Claude 会话",
            "等待中", "工作中", "完成",
            "刷新", "退出",
            "Claude 正在等你", "通知",
            "活动会话", "点击会话以跳转", "检查更新…", "已是最新版本",
            "无法检查更新", "zh"),
        ["ko"] = new(
            "작업 중…", "질문 중", "완료",
            "활성 Claude 세션 없음",
            "대기 중", "작업 중", "완료",
            "새로고침", "종료",
            "Claude가 기다리고 있습니다", "알림",
            "활성 세션", "세션을 클릭하여 이동", "업데이트 확인…", "최신 버전입니다",
            "업데이트를 확인할 수 없습니다", "ko"),
    };
}
