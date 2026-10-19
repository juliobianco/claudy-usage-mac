import Foundation

// All the words the app shows, in one place. `L.t("key", args...)` returns the text for the chosen language,
// falling back to English, then to the key itself. Adding a language is one more table.
// Text from outside (Claude Code's changelog, Anthropic's status incidents, session names) is shown as it comes.

enum L {
    static let languages: [(id: String, name: String)] = [("en", "English"), ("pt", "Português")]

    /// "auto" follows the system's first language.
    static var current: String {
        let chosen = Prefs.shared.language
        if chosen != "auto" { return chosen }
        let first = Locale.preferredLanguages.first ?? "en"
        return first.hasPrefix("pt") ? "pt" : "en"
    }

    static var locale: Locale { Locale(identifier: current == "pt" ? "pt_BR" : "en_US") }

    static func t(_ key: String, _ args: CVarArg...) -> String {
        let lang = current
        let fmt = table[lang]?[key] ?? claudeTable[lang]?[key] ?? table["en"]![key] ?? claudeTable["en"]?[key] ?? key
        return args.isEmpty ? fmt : String(format: fmt, locale: locale, arguments: args)
    }

    /// "1 session", "3 sessions": the word follows the count.
    static func word(_ key: String, _ n: Int) -> String { t(n == 1 ? key + ".one" : key + ".many") }
    static func count(_ key: String, _ n: Int) -> String { "\(n) \(word(key, n))" }

    nonisolated(unsafe) private static var formatters: [String: DateFormatter] = [:]
    /// A formatter in the chosen language ("EEE HH:mm"), cached per language.
    static func date(_ format: String) -> DateFormatter {
        let k = current + "|" + format
        if let f = formatters[k] { return f }
        let f = DateFormatter(); f.locale = locale; f.dateFormat = format
        formatters[k] = f
        return f
    }

    static let table: [String: [String: String]] = [
        "en": [
            "app.title": "CLAUDE USAGE", "week": "WEEK", "fableWeek": "FABLE · WEEK", "sessions": "SESSIONS",
            "none": "none running", "session.one": "session", "session.many": "sessions",
            "request.one": "request", "request.many": "requests",
            "working": "working", "waiting": "waiting", "waitingForYou": "waiting for you", "idle": "idle",
            "more": "+%d more", "loading": "loading...", "noData": "no data", "noDataWhy": "no data: %@",
            "pace.session.hits": "at this pace: 100%% at %@", "pace.session.safe": "at this pace: fine until the reset",
            "pace.week.hits": "at the week's average: 100%% on %@", "pace.week.safe": "at the week's average: fine until the reset",
            "resetsIn": "resets in %@", "windowClosed": "window closed", "resetsSoon": "resets soon", "stale": "stale",
            "status.ok": "All Claude systems operational", "status.loading": "status: loading...",
            "status.offline": "status: no connection", "status.open": "Open status.claude.com",
            "version.latest": "v%@ · latest", "version.available": "v%@ → v%@ available · update", "updating": "updating...",
            "changes.none": "A newer Claude Code is out. Click to run `claude update`.",
            "changes.head": "What's new (click to run `claude update`):", "changes.more": "…and %d more",
            "account.out": "not logged in: claude /login",
            "details": "Details", "period.day": "24 hours", "period.week": "7 days", "thisComputer": "this computer",
            "thisComputer.tip": "Claude Code's own estimate from the sessions on this Mac. It leaves out other devices and claude.ai.",
            "profile": "USAGE PROFILE",
            "profile.info.title": "How to read this",
            "profile.info.ctx": "Context over %@ — share of your usage spent while the conversation was already that long. Long conversations cost more per message.",
            "profile.info.always": "Always-on over %@ — share spent on context loaded at the start of every message (CLAUDE.md, memory, MCP tools, skills) once it passes that size.",
            "profile.info.subagent": "Subagent-heavy — share that came from sessions that ran many subagents.",
            "profile.info.long": "Sessions of %@h+ — share that came from sessions kept open for that long.",
            "profile.info.note": "They overlap, so they do not add up to 100%. Approximate, from sessions on this Mac; it leaves out other devices and claude.ai.",
            "share.ctx": "Context over %@", "share.always": "Always-on over %@", "share.subagent": "Subagent-heavy", "share.long": "Sessions of %@h+",
            "limits.day": "LIMITS · 24 HOURS", "limits.week": "LIMITS · THIS WEEK", "hist.resets": "resets %@", "projects7": "PROJECTS · 7 DAYS",
            "projects.tip": "Share of the week's usage on this computer, estimated from tokens and model prices",
            "nothingYet": "nothing yet", "counting": "counting...", "skillsMcp": "Skills, plugins & MCP", "noDataYet": "no data yet",
            "top.skills": "TOP SKILLS", "top.plugins": "TOP PLUGINS", "top.mcp": "TOP MCP SERVERS", "top.subagents": "TOP SUBAGENTS",
            "hist.starts": "the history starts now", "hist.since": "since %@", "hist.5h": "5h", "hist.week": "week",
            "alerts.title": "Alerts", "alerts.animate": "Animate the menu bar and the widget",
            "alerts.animate.hint": "A yellow ? that blinks when a session waits for you; confetti when a limit starts over.",
            "alerts.notifyWaiting": "Notify me when a session waits for you", "alerts.notifyReset": "Notify me when a limit resets",
            "alerts.previewWaiting": "Preview: waiting for you", "alerts.previewReset": "Preview: limit reset",
            "alert.reset": "limit reset", "alert.resetEarly": "reset ahead of time", "notify.waiting": "Claude is waiting for you",
            "notify.session": "Your 5-hour limit started over.", "notify.week": "Your weekly limit started over.",
            "float.title": "Floating widget", "float.show": "Show on screen", "float.top": "Always on top", "float.glass": "Liquid Glass",
            "float.glass.hint": "Needs macOS 26 or later; otherwise the theme's background is used.", "float.opacity": "Opacity",
            "float.pin": "Float on screen", "float.collapse": "Fold into a bubble", "float.expand": "Unfold", "float.close": "Close", "menu.float": "Floating widget",
            "menu.refresh": "Refresh now", "menu.launch": "Launch at login", "menu.settings": "Settings…", "menu.quit": "Quit Claudy",
            "tip.noWeather": "no weather data", "tip.wind": "wind %d m/s", "tip.sun": "sunrise %@ · sunset %@", "tip.moon": "%@, %d%% lit",
            "moon.0": "new moon", "moon.1": "waxing crescent", "moon.2": "first quarter", "moon.3": "waxing gibbous",
            "moon.4": "full moon", "moon.5": "waning gibbous", "moon.6": "last quarter", "moon.7": "waning crescent",
            "wx.clear": "clear", "wx.mostlyClear": "mostly clear", "wx.partly": "partly cloudy", "wx.overcast": "overcast",
            "wx.fog": "fog", "wx.drizzle": "drizzle", "wx.iceDrizzle": "freezing drizzle", "wx.rain": "rain",
            "wx.iceRain": "freezing rain", "wx.snow": "snow", "wx.grains": "snow grains", "wx.showers": "rain showers",
            "wx.snowShowers": "snow showers", "wx.storm": "thunderstorm", "wx.code": "weather code",
            // settings
            "set.title": "Settings", "tab.look": "Look", "tab.bar": "Menu bar", "tab.system": "System", "tab.claude": "Claude Code",
            "set.language": "Language", "lang.auto": "Automatic", "set.theme": "Theme", "theme.auto": "By season",
            "theme.classic": "Classic", "theme.oled": "OLED black", "theme.midnight": "Midnight", "theme.mocha": "Mocha",
            "theme.forest": "Forest", "theme.halloween": "Halloween", "set.accent": "Accent colour", "accent.theme": "Theme's own",
            "set.skin": "Clawd's skin", "skin.classic": "Classic", "skin.own": "Your own", "skin.ownTip": "Open the skins folder",
            "set.barStyle": "Menu bar label", "style.bars": "Bars", "style.barsNum": "Bars + numbers", "style.numbers": "Numbers",
            "set.show": "In the panel", "show.clawd": "Clawd", "show.sky": "Sky and weather behind him",
            "show.sessions": "Running sessions", "show.status": "Anthropic status", "show.account": "Plan and account",
            "show.fable": "Fable weekly limit", "show.fable.hint": "Only appears when your plan has a separate Fable limit and /usage reports it.",
            "show.details": "Usage details", "set.colours": "Bar colours", "set.warn": "Yellow from", "set.crit": "Red from",
            "set.colours.hint": "The session bar and the big percentage turn yellow, then red, at these levels. The two bars in the menu bar follow the same colours. Now at %d%%.",
            "set.colours.reset": "Back to 60 / 85", "set.launch": "Launch at login", "set.weather": "Weather place", "weather.auto": "Automatic (location)",
            "weather.manual": "Fixed place", "weather.lat": "Latitude", "weather.lon": "Longitude",
            "set.history": "7-day history", "history.clear": "Clear", "history.clear.tip": "Forget the saved 5h and week samples",
            "hist.samples": "%d samples", "set.files": "Files", "open.log": "Open log", "open.data": "Open data folder",
            "set.about": "Claudy Usage %@ · a macOS port of clawd-usage-winwidget (MIT). Clawd and Claude are Anthropic's.",
            "set.moreHint": "The rest of Claude Code's settings (hooks, permissions, plugins, env) are in settings.json",
        ],
        "pt": [
            "app.title": "USO DO CLAUDE", "week": "SEMANA", "fableWeek": "FABLE · SEMANA", "sessions": "SESSÕES",
            "none": "nenhuma rodando", "session.one": "sessão", "session.many": "sessões",
            "request.one": "requisição", "request.many": "requisições",
            "working": "trabalhando", "waiting": "esperando", "waitingForYou": "esperando você", "idle": "parada",
            "more": "+%d", "loading": "carregando...", "noData": "sem dados", "noDataWhy": "sem dados: %@",
            "pace.session.hits": "nesse ritmo: 100%% às %@", "pace.session.safe": "nesse ritmo: tranquilo até o reset",
            "pace.week.hits": "na média da semana: 100%% em %@", "pace.week.safe": "na média da semana: tranquilo até o reset",
            "resetsIn": "reinicia em %@", "windowClosed": "janela fechada", "resetsSoon": "reinicia já", "stale": "desatualizado",
            "status.ok": "Todos os sistemas do Claude operacionais", "status.loading": "status: carregando...",
            "status.offline": "status: sem conexão", "status.open": "Abrir status.claude.com",
            "version.latest": "v%@ · atualizada", "version.available": "v%@ → v%@ disponível · atualizar", "updating": "atualizando...",
            "changes.none": "Há um Claude Code mais novo. Clique para rodar `claude update`.",
            "changes.head": "Novidades (clique para rodar `claude update`):", "changes.more": "…e mais %d",
            "account.out": "sem login: claude /login",
            "details": "Detalhes", "period.day": "24 horas", "period.week": "7 dias", "thisComputer": "este computador",
            "thisComputer.tip": "Estimativa do próprio Claude Code, com base nas sessões deste Mac. Não inclui outros aparelhos nem o claude.ai.",
            "profile": "PERFIL DE USO",
            "profile.info.title": "Como ler isto",
            "profile.info.ctx": "Contexto acima de %@ — parte do seu uso gasta quando a conversa já estava desse tamanho. Conversas longas custam mais por mensagem.",
            "profile.info.always": "Sempre ativo acima de %@ — parte gasta com o contexto carregado no início de toda mensagem (CLAUDE.md, memória, ferramentas MCP, skills) depois que passa desse tamanho.",
            "profile.info.subagent": "Muitos subagentes — parte que veio de sessões que rodaram muitos subagentes.",
            "profile.info.long": "Sessões de %@h+ — parte que veio de sessões mantidas abertas por esse tempo.",
            "profile.info.note": "Elas se sobrepõem, por isso não somam 100%. É uma estimativa das sessões deste Mac; não inclui outros aparelhos nem o claude.ai.",
            "share.ctx": "Contexto acima de %@", "share.always": "Sempre ativo acima de %@", "share.subagent": "Muitos subagentes", "share.long": "Sessões de %@h+",
            "limits.day": "LIMITES · 24 HORAS", "limits.week": "LIMITES · ESTA SEMANA", "hist.resets": "reinicia %@", "projects7": "PROJETOS · 7 DIAS",
            "projects.tip": "Parte do uso da semana neste computador, estimada por tokens e preços dos modelos",
            "nothingYet": "nada ainda", "counting": "contando...", "skillsMcp": "Skills, plugins e MCP", "noDataYet": "ainda sem dados",
            "top.skills": "SKILLS MAIS USADAS", "top.plugins": "PLUGINS MAIS USADOS", "top.mcp": "SERVIDORES MCP MAIS USADOS", "top.subagents": "SUBAGENTES MAIS USADOS",
            "hist.starts": "o histórico começa agora", "hist.since": "desde %@", "hist.5h": "5h", "hist.week": "semana",
            "alerts.title": "Avisos", "alerts.animate": "Animar a barra de menu e o widget",
            "alerts.animate.hint": "Um ? amarelo que pisca quando uma sessão espera por você; confete quando um limite recomeça.",
            "alerts.notifyWaiting": "Avisar quando uma sessão esperar por mim", "alerts.notifyReset": "Avisar quando um limite renovar",
            "alerts.previewWaiting": "Ver: esperando você", "alerts.previewReset": "Ver: limite renovado",
            "alert.reset": "limite renovado", "alert.resetEarly": "renovado antes da hora", "notify.waiting": "O Claude está esperando você",
            "notify.session": "Seu limite de 5 horas recomeçou.", "notify.week": "Seu limite semanal recomeçou.",
            "float.title": "Widget flutuante", "float.show": "Mostrar na tela", "float.top": "Sempre por cima", "float.glass": "Liquid Glass",
            "float.glass.hint": "Precisa do macOS 26 ou mais novo; senão usa o fundo do tema.", "float.opacity": "Opacidade",
            "float.pin": "Deixar flutuando", "float.collapse": "Recolher em bolha", "float.expand": "Expandir", "float.close": "Fechar", "menu.float": "Widget flutuante",
            "menu.refresh": "Atualizar agora", "menu.launch": "Abrir ao iniciar o Mac", "menu.settings": "Ajustes…", "menu.quit": "Sair do Claudy",
            "tip.noWeather": "sem dados do clima", "tip.wind": "vento %d m/s", "tip.sun": "nascer do sol %@ · pôr do sol %@", "tip.moon": "%@, %d%% iluminada",
            "moon.0": "lua nova", "moon.1": "lua crescente", "moon.2": "quarto crescente", "moon.3": "crescente gibosa",
            "moon.4": "lua cheia", "moon.5": "minguante gibosa", "moon.6": "quarto minguante", "moon.7": "lua minguante",
            "wx.clear": "céu limpo", "wx.mostlyClear": "quase limpo", "wx.partly": "parcialmente nublado", "wx.overcast": "nublado",
            "wx.fog": "neblina", "wx.drizzle": "garoa", "wx.iceDrizzle": "garoa congelante", "wx.rain": "chuva",
            "wx.iceRain": "chuva congelante", "wx.snow": "neve", "wx.grains": "grãos de neve", "wx.showers": "pancadas de chuva",
            "wx.snowShowers": "pancadas de neve", "wx.storm": "tempestade", "wx.code": "código do tempo",
            "set.title": "Ajustes", "tab.look": "Aparência", "tab.bar": "Barra de menu", "tab.system": "Sistema", "tab.claude": "Claude Code",
            "set.language": "Idioma", "lang.auto": "Automático", "set.theme": "Tema", "theme.auto": "Por estação",
            "theme.classic": "Clássico", "theme.oled": "Preto OLED", "theme.midnight": "Meia-noite", "theme.mocha": "Mocha",
            "theme.forest": "Floresta", "theme.halloween": "Halloween", "set.accent": "Cor de destaque", "accent.theme": "A do tema",
            "set.skin": "Skin do Clawd", "skin.classic": "Clássico", "skin.own": "Suas skins", "skin.ownTip": "Abrir a pasta de skins",
            "set.barStyle": "Rótulo na barra de menu", "style.bars": "Barras", "style.barsNum": "Barras + números", "style.numbers": "Números",
            "set.show": "No painel", "show.clawd": "Clawd", "show.sky": "Céu e clima atrás dele",
            "show.sessions": "Sessões em andamento", "show.status": "Status da Anthropic", "show.account": "Plano e conta",
            "show.fable": "Limite semanal do Fable", "show.fable.hint": "Só aparece quando o seu plano tem um limite separado do Fable e o /usage informa.",
            "show.details": "Detalhes de uso", "set.colours": "Cores das barras", "set.warn": "Amarelo a partir de", "set.crit": "Vermelho a partir de",
            "set.colours.hint": "A barra da sessão e o número grande ficam amarelos e depois vermelhos nesses níveis. As duas barras da barra de menu seguem as mesmas cores. Agora em %d%%.",
            "set.colours.reset": "Voltar a 60 / 85", "set.launch": "Abrir ao iniciar o Mac", "set.weather": "Local do clima", "weather.auto": "Automático (localização)",
            "weather.manual": "Local fixo", "weather.lat": "Latitude", "weather.lon": "Longitude",
            "set.history": "Histórico de 7 dias", "history.clear": "Apagar", "history.clear.tip": "Esquecer as amostras salvas de 5h e semana",
            "hist.samples": "%d amostras", "set.files": "Arquivos", "open.log": "Abrir o log", "open.data": "Abrir a pasta de dados",
            "set.about": "Claudy Usage %@ · um port para macOS do clawd-usage-winwidget (MIT). Clawd e Claude são da Anthropic.",
            "set.moreHint": "O resto das configurações do Claude Code (hooks, permissões, plugins, env) fica no settings.json",
        ],
    ]
}
