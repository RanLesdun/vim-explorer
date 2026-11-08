#Requires AutoHotkey v2.0
#SingleInstance Force
SetKeyDelay(-1)

; ============================================================
;  VIM для Проводника Windows 10 (AutoHotkey v2)
;  Режимы: NORMAL / VISUAL / INSERT
;  Ctrl+Alt+V  - вкл/выкл весь скрипт
; ============================================================

global mode := "normal"      ; normal | visual | insert
global cnt := ""             ; счётчик (5j)
global pend := ""            ; ожидающий оператор (g, y, d, z)
global ribbonFlag := false   ; мы "внутри" ленты
global addrFlag := false     ; фокус в адресной строке / поиске

^!v:: Suspend()

; ---------- вспомогательное ----------
InExplorer() => WinActive("ahk_class CabinetWClass")

FocusClass() {
    try {
        h := ControlGetFocus("A")
        return h ? ControlGetClassNN(h) : ""
    } catch
        return ""
}

; list | tree | ribbon | edit | "" (прочее)
GetCtx() {
    global ribbonFlag
    c := FocusClass()
    if InStr(c, "DirectUIHWND") || InStr(c, "NetUIHWND")
        return (ribbonFlag || InStr(c, "NetUIHWND")) ? "ribbon" : "list"
    if InStr(c, "SysTreeView32") {
        ribbonFlag := false
        return "tree"
    }
    if InStr(c, "Edit") {
        ribbonFlag := false
        return "edit"
    }
    return ""
}

NormalCtx(*) => InExplorer() && mode != "insert" && (c := GetCtx()) != "" && c != "edit"
InsertCtx(*) => InExplorer() && mode = "insert"
EditCtx(*) {
    if !InExplorer()
        return false
    c := GetCtx()
    return (c = "edit" || c = "")
}

FocusList() {
    try ControlFocus("DirectUIHWND1", "A")
}

Tip(txt) {
    ToolTip(txt)
    SetTimer(() => ToolTip(), -1200)
}

; ---------- регистрация клавиш ----------
HotIf(NormalCtx)

for ch in StrSplit("ABCDEFGHIJKLMNOPQRSTUVWXYZ") {
    vk := Format("vk{:02X}", Ord(ch))        ; по VK -> работает и на русской раскладке
    Hotkey("$" vk, Handle.Bind(StrLower(ch)))
    Hotkey("$+" vk, Handle.Bind(ch))
}
for ch in StrSplit("0123456789")
    Hotkey("$vk" Format("{:02X}", Ord(ch)), Handle.Bind(ch))

Hotkey("$vkBD", Handle.Bind("-"))
Hotkey("$vkBF", Handle.Bind("/"))
Hotkey("$vkBE", Handle.Bind("."))

for ch in ["d", "u", "r"]
    Hotkey("$^vk" Format("{:02X}", Ord(StrUpper(ch))), Handle.Bind("^" ch))

Hotkey("$Tab", (*) => Send("{F6}"))
Hotkey("$Space", (*) => (GetCtx() = "list" ? Send("^{Space}") : 0))
Hotkey("$Esc", EscNormal)

HotIf(InsertCtx)
Hotkey("$Esc", (*) => SetMode("normal"))

HotIf(EditCtx)
Hotkey("~Esc", (*) => SetTimer(BackToList, -60))
Hotkey("~Enter", (*) => SetTimer(BackToList, -60))

HotIf()

; ---------- логика ----------
SetMode(m) {
    global mode := m
}

BackToList() {
    global addrFlag
    if addrFlag {
        addrFlag := false
        FocusList()
    }
}

EscNormal(*) {
    global mode, cnt, pend, ribbonFlag
    cnt := "", pend := ""
    wasRibbon := ribbonFlag || GetCtx() = "ribbon"
    if (mode = "visual")
        mode := "normal"
    if wasRibbon
        Send("{Esc}")
    ribbonFlag := false
    if (GetCtx() != "list")
        FocusList()
}

Handle(key, *) {
    global mode, cnt, pend
    ctx := GetCtx()
    if (ctx = "" || ctx = "edit")
        return

    ; --- цифры = счётчик ---
    if (key ~= "^\d$") && !(key = "0" && cnt = "") {
        cnt .= key
        return
    }
    n := (cnt = "") ? 1 : Integer(cnt)
    hadCount := (cnt != "")

    ; --- второй символ комбинации (gg, yy, dd, gl ...) ---
    if (pend != "") {
        combo := pend key
        pend := "", cnt := ""
        DoCombo(combo, ctx, n)
        return
    }

    ; --- visual: y/d срабатывают сразу ---
    if (mode = "visual" && (key = "y" || key = "d")) {
        Send(key = "y" ? "^c" : "^x")
        mode := "normal", cnt := ""
        return
    }

    ; --- начало комбинации ---
    if InStr("gydz", key, true) {
        pend := key
        return
    }

    cnt := ""
    Single(key, ctx, n, hadCount)
}

DoCombo(c, ctx, n) {
    global mode, addrFlag, ribbonFlag
    vis := (mode = "visual") ? "+" : ""
    switch c {
        case "gg":
            Send(vis "{Home}")
        case "gl":                       ; адресная строка
            addrFlag := true, ribbonFlag := false
            Send("^l")
        case "gn":                       ; боковая панель
            ribbonFlag := false
            try ControlFocus("SysTreeView321", "A")
            catch
                Tip("Боковая панель не найдена (скрыта?)")
        case "gf":                       ; назад к списку файлов
            ribbonFlag := false
            FocusList()
        case "gr":                       ; лента (Alt -> стрелки)
            ribbonFlag := true
            Send("{Alt}")
        case "zr":                       ; свернуть/развернуть ленту
            Send("^{F1}")
        case "zh":                       ; скрытые файлы
            ToggleHidden()
        case "yy":
            if (ctx = "list") {
                Send("^c"), Tip("yanked")
            }
        case "dd":
            if (ctx = "list") {
                Send("^x"), Tip("cut")
            }
        case "yp":
            if (ctx = "list")
                CopyPath()
    }
}

Single(key, ctx, n, hadCount) {
    global mode, addrFlag, ribbonFlag
    vis := (mode = "visual") ? "+" : ""

    ; вне списка файлов работает только навигация
    if (ctx != "list" && !InStr("hjklo", key, true))
        return

    switch key {
        case "j": Send(vis "{Down " n "}")
        case "k": Send(vis "{Up " n "}")
        case "h":
            if (ctx = "list" && mode != "visual") {
                Loop n {
                    Send("!{Up}")
                    Sleep(80)
                }
            } else
                Send("{Left " n "}")
        case "l":
            if (ctx = "list" && mode != "visual")
                Send("{Enter}")
            else
                Send("{Right " n "}")
        case "o": Send("{Enter}")
        case "G":
            if hadCount {
                Send("{Home}")
                if (n > 1)
                    Send("{Down " (n - 1) "}")
            } else
                Send(vis "{End}")
        case "0": Send(vis "{Home}")
        case "-": Send("!{Up}")          ; на уровень выше
        case "H": Send("!{Left}")        ; назад
        case "L": Send("!{Right}")       ; вперёд
        case "^d": Send(vis "{PgDn}")
        case "^u": Send(vis "{PgUp}")
        case "v": mode := (mode = "visual") ? "normal" : "visual"
        case "V": Send("^a")
        case "p": Send("^v")
        case "u": Send("^z")
        case "^r": Send("^y")
        case "x": Send("{Delete}")
        case "X": Send("+{Delete}")
        case "r": Send("{F2}")           ; переименовать
        case "a": Send("^+n")            ; новая папка
        case "R": Send("{F5}")
        case "i": mode := "insert"       ; печатаем (поиск по первой букве)
        case "/":
            addrFlag := true
            Send("^e")                   ; поиск
    }
}

ToggleHidden() {
    k := "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    v := RegRead(k, "Hidden", 2)
    RegWrite(v = 1 ? 2 : 1, "REG_DWORD", k, "Hidden")
    Send("{F5}")
    Tip(v = 1 ? "скрытые: выкл" : "скрытые: вкл")
}

CopyPath() {
    A_Clipboard := ""
    Send("^c")
    if !ClipWait(1)
        return
    A_Clipboard := A_Clipboard           ; в текст (пути)
    Tip("path copied")
}

; ---------- индикатор режима ----------
SetTimer(UpdateStatus, 150)
UpdateStatus() {
    static last := ""
    if !InExplorer() {
        if (last != "") {
            ToolTip()
            last := ""
        }
        return
    }
    WinGetPos(&x, &y, &w, &h, "A")
    t := "-- " StrUpper(mode) " --  [" GetCtx() "]  " cnt pend
    key := t "|" x "," y "," h
    if (key = last)
        return
    last := key
    ToolTip(t, x + 12, y + h - 60)
}
