#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; ======================================================================================================================
; 脚本名称：
;     软件亮度热键（基于 Windows Gamma Ramp 的桌面输出层亮度调节）——常用区间重映射版
;
; 设备与任务背景：
;     用户使用 MSI Titan 18 Pro 2024 笔记本，搭载 RTX 4070 Laptop 显卡与 4K MiniLED 内屏。
;     这块屏幕的实际亮度能力跨度极大，但 Windows 自带系统亮度滑条可调范围不够用：
;         1. 有时最低亮度仍然太亮；
;         2. 有时最高亮度仍然不够亮；
;         3. 用户日常工作会频繁在较暗与较亮之间切换。
;
; 原始工作流：
;     过去用户主要通过 NVIDIA 控制面板：
;         “显示” -> “调整桌面颜色设置” -> “应用色彩增强” -> “亮度”
;     来手动改变桌面整体观感亮度。
;     这种方法有效，但每次都要打开控制面板、等待载入、进入页面、拖动滑条、点击应用，
;     高频使用时非常麻烦。
;
; 本脚本的目标：
;     用快捷键快速替代“手动打开 NVIDIA 控制面板调亮度”的流程。
;     推荐用法是：
;         1. 先把 Windows 自带系统亮度固定在一个中间值，例如 50% 左右；
;         2. 后续基本不再频繁碰 Windows 系统亮度；
;         3. 日常只用本脚本的热键快速改变桌面输出层的软件亮度。
;
; 目前绑定的热键：
;     Alt + 数字小键盘 +
;         -> 增加软件亮度 stepSize
;
;     Alt + 数字小键盘 -
;         -> 降低软件亮度 stepSize
;
;     Alt + 数字小键盘 *
;         -> 手动刷新当前软件亮度，不改变数值
;         -> 用于应对 Windows 设置、系统栏、驱动事件等偶尔覆盖 Gamma Ramp 的情况。
;
;     Alt + 数字小键盘 /
;         -> 临时恢复为“无本脚本介入”的标准显示映射
;         -> 不改变当前 level，不写入 ini
;         -> 直到下次触发 Alt + *、Alt + + 或 Alt + -，脚本才会重新应用软件亮度。
;
; 数值设计：
;     本脚本把“软件亮度”抽象为 0 ~ 1000 的内部控制标尺。
;     这个数值不是 Windows 亮度百分比，也不是显示器真实 nits，只是脚本内部使用的控制值。
;
; 本版的关键变化：常用区间重映射
;     实际使用一个月后发现，旧版脚本日常主要使用 200 ~ 600 的亮度值。
;     如果继续在线性 0 ~ 1000 标尺中使用这段区间，常用范围只占 40%，微调空间不足。
;
;     因此本版加入“控制值 -> 有效视觉值”的分段映射：
;
;         新版控制值 0      -> 旧版视觉值 0
;         新版控制值 100    -> 旧版视觉值 200
;         新版控制值 900    -> 旧版视觉值 600
;         新版控制值 1000   -> 旧版视觉值 1000
;
;     换句话说：
;         旧版 200 ~ 600 的常用视觉区间
;         现在被摊开到新版 100 ~ 900。
;
;     这样做的结果：
;         - 日常最常用的亮度范围拥有更多档位；
;         - 极暗区间 0 ~ 100 仍然存在，但变得更“陡”；
;         - 极亮区间 900 ~ 1000 仍然存在，但也变得更“陡”。
;
; 重要理解：
;     本脚本显示、保存、热键调整的是“新版控制值”。
;     真正送入旧 Gamma Ramp 公式的是“映射后的有效视觉值”。
;
;     例如：
;         新版控制值 100  约等于旧版视觉值 200
;         新版控制值 500  约等于旧版视觉值 400
;         新版控制值 900  约等于旧版视觉值 600
;
;     所以新版 500 不再等于旧版 500 的视觉效果。
;     旧版 500 的视觉效果，在新版里大约对应控制值 700。
;
; 自动迁移旧配置：
;     当前亮度值保存在脚本所在目录下的 GpuBrightness.ini。
;     如果 ini 里没有 MapVersion，脚本会认为它来自旧版。
;     首次运行本版时，脚本会把旧 Level 自动转换成新版控制值，
;     尽量避免第一次启动新版脚本时画面亮度突然跳变。
;
; 工作原理：
;     本脚本调用 Windows 的 SetDeviceGammaRamp API，修改整个桌面输出的 Gamma Ramp。
;     简单理解，就是对送往屏幕的图像信号做一次整体映射，从而改变“看起来有多亮/多暗”。
;
;     它不是：
;         - 直接调笔记本面板背光；
;         - 直接调用 NVIDIA 控制面板内部私有接口；
;         - 直接同步修改 NVIDIA 控制面板中显示的亮度数值。
;
;     因此应把它理解为“软件亮度热键”，而不是“物理背光热键”。
;
; 已知局限性：
;     1. 某些程序、驱动事件、分辨率变化、显示模式切换、HDR 开关、色彩管理软件、远程桌面、
;        或 Windows 系统界面，有可能覆盖或重置当前 Gamma Ramp。
;     2. 如果发生“突然失效”，通常不是脚本坏了，而是系统把 Gamma Ramp 覆盖了。
;     3. 此时按 Alt + 数字小键盘 * 可手动刷新当前亮度，不需要先调亮再调暗。
;     4. 如果想主动临时查看“无本脚本介入”的默认观感，按 Alt + 数字小键盘 /。
;     5. 本脚本影响整个桌面输出，不只影响某一个软件。
;     6. 它和 NVIDIA 控制面板中的视觉效果会相似，但不保证逐点完全一致。
;
; 当前核心设计原则：
;     尽量少热键、尽量少配置、尽量适合高频日常使用。
;     因此目前只保留：
;         Alt + 小键盘 +
;         Alt + 小键盘 -
;         Alt + 小键盘 *
;         Alt + 小键盘 /
; ======================================================================================================================

global levelFile := A_ScriptDir "\GpuBrightness.ini"

; 当前映射版本。用于判断 ini 是否需要从旧版自动迁移。
global mapVersion := 2

; 总控制范围。保持 0 ~ 1000 不变。
global minLevel := 0
global maxLevel := 1000

; 旧版中实际常用的视觉区间。
global oldUsefulLow := 200
global oldUsefulHigh := 600

; 新版中希望展开后的常用控制区间。
global newUsefulLow := 100
global newUsefulHigh := 900

; 默认启动亮度。这里是新版控制值，不是旧版视觉值。
global defaultLevel := 500

; 每次热键调整的步长。以后要改步长，只改这一行。
global stepSize := 40

; 提示框持续时间，单位毫秒。
global tipMs := 700

global level := LoadLevel()

ApplyLevel(level)

; 主热键：Alt + 小键盘 +/-，每次 ±stepSize
!NumpadAdd::Step(stepSize)
!NumpadSub::Step(-stepSize)

; 手动刷新当前软件亮度：Alt + 小键盘 *
!NumpadMult::RefreshLevel()

; 临时恢复无脚本介入效果：Alt + 小键盘 /
!NumpadDiv::ResetGammaRamp()

Step(delta){
    global level
    SetLevel(level+delta)
}

RefreshLevel(){
    global level
    ApplyLevel(level)
    ShowTip("软件亮度刷新: " level)
}

ResetGammaRamp(){
    ApplyIdentityGammaRamp()
    ShowTip("软件亮度暂停")
}

SetLevel(v){
    global level, levelFile, mapVersion

    v:=RoundToStep(v)
    v:=ClampLevel(v)

    level:=v
    ApplyLevel(level)

    IniWrite(level, levelFile, "Main", "Level")
    IniWrite(mapVersion, levelFile, "Main", "MapVersion")

    ShowTip("软件亮度: " level)
}

LoadLevel(){
    global levelFile, mapVersion, defaultLevel

    raw:=IniRead(levelFile, "Main", "Level", "")

    if raw=""{
        return ClampLevel(defaultLevel)
    }

    try v:=Integer(raw)
    catch
        v:=defaultLevel

    storedVersion:=IniRead(levelFile, "Main", "MapVersion", "1")

    ; 如果 ini 来自旧版，则把旧版 Level 转换成新版控制值，尽量保持视觉亮度不跳变。
    if storedVersion!=String(mapVersion){
        v:=MapEffectiveToControl(v)
        v:=RoundToStep(v)
        v:=ClampLevel(v)

        IniWrite(v, levelFile, "Main", "Level")
        IniWrite(mapVersion, levelFile, "Main", "MapVersion")
    }

    return ClampLevel(v)
}

RoundToStep(v){
    global stepSize
    return Round(v/stepSize)*stepSize
}

ClampLevel(v){
    global minLevel, maxLevel

    if v<minLevel
        return minLevel

    if v>maxLevel
        return maxLevel

    return v
}

MapControlToEffective(controlLevel){
    global minLevel, maxLevel
    global oldUsefulLow, oldUsefulHigh
    global newUsefulLow, newUsefulHigh

    c:=ClampLevel(controlLevel)

    ; 新版 0 ~ 100 映射到旧版 0 ~ 200
    if c<=newUsefulLow{
        return Lerp(minLevel, oldUsefulLow, (c-minLevel)/(newUsefulLow-minLevel))
    }

    ; 新版 100 ~ 900 映射到旧版 200 ~ 600
    if c<=newUsefulHigh{
        return Lerp(oldUsefulLow, oldUsefulHigh, (c-newUsefulLow)/(newUsefulHigh-newUsefulLow))
    }

    ; 新版 900 ~ 1000 映射到旧版 600 ~ 1000
    return Lerp(oldUsefulHigh, maxLevel, (c-newUsefulHigh)/(maxLevel-newUsefulHigh))
}

MapEffectiveToControl(effectiveLevel){
    global minLevel, maxLevel
    global oldUsefulLow, oldUsefulHigh
    global newUsefulLow, newUsefulHigh

    e:=ClampLevel(effectiveLevel)

    ; 旧版 0 ~ 200 映射回新版 0 ~ 100
    if e<=oldUsefulLow{
        return Lerp(minLevel, newUsefulLow, (e-minLevel)/(oldUsefulLow-minLevel))
    }

    ; 旧版 200 ~ 600 映射回新版 100 ~ 900
    if e<=oldUsefulHigh{
        return Lerp(newUsefulLow, newUsefulHigh, (e-oldUsefulLow)/(oldUsefulHigh-oldUsefulLow))
    }

    ; 旧版 600 ~ 1000 映射回新版 900 ~ 1000
    return Lerp(newUsefulHigh, maxLevel, (e-oldUsefulHigh)/(maxLevel-oldUsefulHigh))
}

Lerp(a,b,t){
    return a+(b-a)*t
}

ShowTip(txt){
    global tipMs
    ToolTip(txt)
    SetTimer(ClearTip, -tipMs)
}

ClearTip(){
    ToolTip()
}

ApplyLevel(level){
    hdc:=DllCall("GetDC", "ptr", 0, "ptr")
    ramp:=Buffer(256*3*2, 0)

    ; 关键：这里不再直接把新版 level 送进旧视觉公式。
    ; 而是先把新版控制值映射成旧版有效视觉值。
    effectiveLevel:=MapControlToEffective(level)

    dark:=(500-effectiveLevel>0)?(500-effectiveLevel)/500.0:0.0
    bright:=(effectiveLevel-500>0)?(effectiveLevel-500)/500.0:0.0

    gamma:=1.0 + dark*1.20 - bright*0.50
    gain:=1.0 - dark*0.85 + bright*0.25
    lift:=bright*0.08

    Loop 256{
        i:=A_Index-1
        x:=i/255.0
        y:=(x**gamma)*gain + lift

        if y<0
            y:=0
        else if y>1
            y:=1

        v:=Round(y*65535)

        NumPut("ushort", v, ramp, i*2)
        NumPut("ushort", v, ramp, (256+i)*2)
        NumPut("ushort", v, ramp, (512+i)*2)
    }

    DllCall("gdi32\SetDeviceGammaRamp", "ptr", hdc, "ptr", ramp)
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdc)
}

ApplyIdentityGammaRamp(){
    hdc:=DllCall("GetDC", "ptr", 0, "ptr")
    ramp:=Buffer(256*3*2, 0)

    Loop 256{
        i:=A_Index-1
        v:=Round((i/255.0)*65535)

        NumPut("ushort", v, ramp, i*2)
        NumPut("ushort", v, ramp, (256+i)*2)
        NumPut("ushort", v, ramp, (512+i)*2)
    }

    DllCall("gdi32\SetDeviceGammaRamp", "ptr", hdc, "ptr", ramp)
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdc)
}