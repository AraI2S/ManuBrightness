#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; ======================================================================================================================
; 脚本名称：
;     ManuBrightness v5.1 —— 平滑常用区间 / 强高亮端（日常模式原版）
;
; 设备与任务背景：
;     用户使用 MSI Titan 18 Pro 2024 笔记本，搭载 RTX 4070 Laptop 显卡与 4K MiniLED 内屏。
;     Windows 自带亮度滑条无法覆盖实际需要的明暗范围，因此本脚本通过 Windows Gamma Ramp，
;     在不频繁改变面板物理背光的情况下，用快捷键改变整个桌面的软件亮度观感。
;
; 基本热键：
;     Alt + 数字小键盘 + ：提高软件亮度 stepSize
;     Alt + 数字小键盘 - ：降低软件亮度 stepSize
;     Alt + 数字小键盘 * ：重新应用当前软件亮度，不改变数值
;     Alt + 数字小键盘 / ：临时恢复“无本脚本介入”的标准显示映射
;
; 数值说明：
;     本脚本使用 0 ~ 1000 的控制标尺。
;     这个数值不是 Windows 亮度百分比，也不是真实 nits，只是脚本内部控制值。
;
; 用来对齐的稳定工作版（MapVersion 2）：
;     该版把控制值映射为“有效视觉值”：
;
;         V2 控制值 0      -> 有效视觉值 0
;         V2 控制值 100    -> 有效视觉值 200
;         V2 控制值 900    -> 有效视觉值 600
;         V2 控制值 1000   -> 有效视觉值 1000
;
;     最关键的参数关系是：
;
;         中间区间 100 ~ 900：
;             有效视觉值斜率 = 400 / 800 = 0.5
;
;         高亮区间 900 ~ 1000：
;             有效视觉值斜率 = 400 / 100 = 4
;
;     也就是说，稳定版的高亮端灵敏度是中间区间的 8 倍。
;     这正是它在 900 以上突然强烈发白、到 960 ~ 1000 时画面元素越来越难分辨的根本原因。
;
; 上一份 V4 方案为什么仍然不够：
;     V4 使用 Hermite 曲线，并把高端终点斜率设成 1.5。
;     相比中间区间约 0.8167 的斜率，它只提高到约 1.84 倍；
;     这比稳定版原本的 8 倍差异温和得多，因而把 800 ~ 1000 拉得过于平均，
;     没有充分复现稳定版高亮端迅速进入“接近全白、细节大量压缩”的性格。
;
; 本版（MapVersion 5）的目标：
;     1. 本版控制值 200 的视觉效果，约等于稳定版控制值 400；
;     2. 本版控制值 800 的视觉效果，约等于稳定版控制值 960；
;     3. 本版 200 ~ 800 是日常使用区间，必须严格平滑、均匀、容易预期；
;     4. 本版 800 ~ 1000 是特殊高亮区，必须迅速冲向极限；
;     5. 尤其到 960 ~ 1000 时，应几乎已经处于最大提亮附近；
;     6. 新旧脚本都保持 0 = 0、1000 = 1000。
;
; 本版采用的最终有效视觉值锚点：
;
;         稳定版控制值 400 -> 有效视觉值 350
;         稳定版控制值 960 -> 有效视觉值 840
;
;     因而本版定义：
;
;         本版控制值 0      -> 有效视觉值 0
;         本版控制值 200    -> 有效视觉值 350
;         本版控制值 800    -> 有效视觉值 840
;         本版控制值 1000   -> 有效视觉值 1000
;
; 常用区间 200 ~ 800：
;     使用严格线性映射：
;
;         200 -> 350
;         800 -> 840
;
;     当前 stepSize = 50 时，每按一次 +/-，有效视觉值固定变化约 40.83。
;     这一段不会在中途突然变快或变慢。
;
; 高亮特殊区间 800 ~ 1000：
;     使用“快速逼近上限”的二次饱和曲线：
;
;         effective = 840 + 160 × [1 - (1 - t)^highExtremePower]
;         t = (control - 800) / 200
;
;     当前 highExtremePower = 2.0 时：
;
;         控制值 800  -> 有效视觉值 840.0
;         控制值 840  -> 有效视觉值 897.6
;         控制值 880  -> 有效视觉值 942.4
;         控制值 920  -> 有效视觉值 974.4
;         控制值 960  -> 有效视觉值 993.6
;         控制值 1000 -> 有效视觉值 1000.0
;
;     这意味着：
;         - 一进入 800 以上，亮度会明显比日常区间更快上升；
;         - 到 920 时已经非常接近极限；
;         - 到 960 时只剩约 6.4 个有效视觉值未用；
;         - 960 ~ 1000 基本都处于最大提亮附近，画面会明显发白、层次被强烈压缩。
;
;     注意：
;         这里从数学上看，曲线靠近 1000 时会逐渐“贴顶”；
;         从视觉上看，它反而会更像稳定版的极端高亮状态，因为大部分画面早已进入削顶、发白区。
;         想让高亮端更早、更猛烈地发白，可提高 highExtremePower，例如改成 2.5；
;         想让 800 ~ 1000 稍微温和一些，可降低到 1.6 ~ 1.8。
;
; 低端特殊区间 0 ~ 200：
;     继续使用平滑 Hermite 曲线：
;         0 -> 0
;         200 -> 350
;
;     接近 0 时灵敏度较高，用于极暗特殊情况；
;     到 200 时平滑接入日常线性区间。
;
; 自动迁移旧配置：
;     当前亮度值保存在脚本所在目录下的 GpuBrightness.ini。
;
;     - MapVersion 5：直接读取；
;     - MapVersion 4：还原上一份 Hermite 高端方案的有效视觉值；
;     - MapVersion 3：还原“200~800 直接对应 V2 400~960”的试验方案；
;     - MapVersion 2：读取稳定工作版控制值；
;     - MapVersion 1 / 无版本：视为直接保存的有效视觉值；
;     - 最后统一反查本版控制值。
;
;     本版反向映射采用二分查找，只在启动迁移时执行，不影响平时热键响应。
;
; 工作原理：
;     脚本调用 SetDeviceGammaRamp，为 R、G、B 三个通道写入同一条非线性映射。
;     有效视觉值低于 500 时进入压暗公式，高于 500 时进入提亮公式。
;
;     gamma：弯折明暗分布；
;     gain ：改变整体增益；
;     lift ：在提亮时少量抬升暗部。
;
; 已知局限性：
;     Windows、显卡驱动、HDR、色彩管理软件、显示模式切换或某些系统界面，
;     可能覆盖当前 Gamma Ramp。发生时按 Alt + 数字小键盘 * 即可重新应用。
;
; 核心设计原则：
;     200 ~ 800 平滑稳定；800 以上快速冲向极限；960 ~ 1000 基本处于近最大提亮状态。
; ======================================================================================================================

global levelFile := A_ScriptDir "\GpuBrightness.ini"

; 当前映射版本。
global mapVersion := 5

; 总控制范围。
global minLevel := 0
global maxLevel := 1000

; 本版日常常用控制区间。
global usefulControlLow := 200
global usefulControlHigh := 800

; 本版日常区间对应的有效视觉值。
; 350 等于稳定版控制值 400 的视觉效果；
; 840 等于稳定版控制值 960 的视觉效果。
global usefulEffectiveLow := 350
global usefulEffectiveHigh := 840

; 低端靠近 0 时的灵敏度。
global lowExtremeSlope := 2.5

; 高亮端“快速逼近最大值”的指数。
; 2.0：当前推荐值；
; 数值越大，800 以上越快接近 1000。
global highExtremePower := 2.0

; 默认启动亮度：本版控制值。
global defaultLevel := 280

; 每次热键调整的步长。
global stepSize := 50

; 提示框持续时间，单位毫秒。
global tipMs := 700

global level := LoadLevel()

ApplyLevel(level)

; Alt + 小键盘 +/-：每次 ±stepSize
!NumpadAdd::Step(stepSize)
!NumpadSub::Step(-stepSize)

; Alt + 小键盘 *：重新应用当前软件亮度
!NumpadMult::RefreshLevel()

; Alt + 小键盘 /：临时恢复无脚本介入效果
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

    try v:=Float(raw)
    catch
        v:=defaultLevel

    storedVersion:=IniRead(levelFile, "Main", "MapVersion", "1")

    if storedVersion=String(mapVersion){
        return ClampLevel(v)
    }

    if storedVersion="4"{
        effectiveLevel:=MapV4ControlToEffective(v)
        v:=MapEffectiveToControl(effectiveLevel)
    } else if storedVersion="3"{
        v2Control:=MapV3ControlToV2Control(v)
        effectiveLevel:=MapV2ControlToEffective(v2Control)
        v:=MapEffectiveToControl(effectiveLevel)
    } else if storedVersion="2"{
        effectiveLevel:=MapV2ControlToEffective(v)
        v:=MapEffectiveToControl(effectiveLevel)
    } else if storedVersion="1"{
        v:=MapEffectiveToControl(v)
    } else {
        v:=defaultLevel
    }

    v:=RoundToStep(v)
    v:=ClampLevel(v)

    IniWrite(v, levelFile, "Main", "Level")
    IniWrite(mapVersion, levelFile, "Main", "MapVersion")

    return v
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

; 稳定工作版（MapVersion 2）控制值 -> 有效视觉值。
MapV2ControlToEffective(controlLevel){
    c:=ClampLevel(controlLevel)

    if c<=100{
        return Lerp(0, 200, c/100)
    }

    if c<=900{
        return Lerp(200, 600, (c-100)/800)
    }

    return Lerp(600, 1000, (c-900)/100)
}

; MapVersion 3 试验版控制值 -> 稳定版 V2 控制值。
MapV3ControlToV2Control(controlLevel){
    c:=ClampLevel(controlLevel)

    if c<=200{
        return Lerp(0, 400, c/200)
    }

    if c<=800{
        return Lerp(400, 960, (c-200)/600)
    }

    return Lerp(960, 1000, (c-800)/200)
}

; MapVersion 4 控制值 -> 有效视觉值。
; 用于兼容上一份“高端 Hermite、终点斜率 1.5”的方案。
MapV4ControlToEffective(controlLevel){
    c:=ClampLevel(controlLevel)
    middleSlope:=(840-350)/(800-200)

    if c<=200{
        return HermiteInterpolate(
            c,
            0,
            200,
            0,
            350,
            2.5,
            middleSlope
        )
    }

    if c<=800{
        return Lerp(350,840,(c-200)/600)
    }

    return HermiteInterpolate(
        c,
        800,
        1000,
        840,
        1000,
        middleSlope,
        1.5
    )
}

; 本版控制值 -> 有效视觉值。
MapControlToEffective(controlLevel){
    global minLevel, maxLevel
    global usefulControlLow, usefulControlHigh
    global usefulEffectiveLow, usefulEffectiveHigh
    global lowExtremeSlope, highExtremePower

    c:=ClampLevel(controlLevel)
    middleSlope:=(usefulEffectiveHigh-usefulEffectiveLow)/(usefulControlHigh-usefulControlLow)

    ; 低端特殊区间：平滑接入 200。
    if c<=usefulControlLow{
        return HermiteInterpolate(
            c,
            minLevel,
            usefulControlLow,
            minLevel,
            usefulEffectiveLow,
            lowExtremeSlope,
            middleSlope
        )
    }

    ; 日常区间：严格线性，保证步长均匀。
    if c<=usefulControlHigh{
        return Lerp(
            usefulEffectiveLow,
            usefulEffectiveHigh,
            (c-usefulControlLow)/(usefulControlHigh-usefulControlLow)
        )
    }

    ; 高亮特殊区间：快速逼近最大值。
    t:=(c-usefulControlHigh)/(maxLevel-usefulControlHigh)

    return usefulEffectiveHigh
        + (maxLevel-usefulEffectiveHigh)
        * (1-(1-t)**highExtremePower)
}

; 有效视觉值 -> 本版控制值。
; 用二分查找求本版单调映射的反函数，主要用于版本迁移。
MapEffectiveToControl(effectiveLevel){
    global minLevel, maxLevel

    target:=ClampLevel(effectiveLevel)
    low:=minLevel
    high:=maxLevel

    Loop 40{
        mid:=(low+high)/2
        mapped:=MapControlToEffective(mid)

        if mapped<target
            low:=mid
        else
            high:=mid
    }

    return (low+high)/2
}

; 三次 Hermite 插值。
HermiteInterpolate(x,x0,x1,y0,y1,slope0,slope1){
    width:=x1-x0
    t:=(x-x0)/width

    h00:=2*t**3-3*t**2+1
    h10:=t**3-2*t**2+t
    h01:=-2*t**3+3*t**2
    h11:=t**3-t**2

    return h00*y0
        + h10*width*slope0
        + h01*y1
        + h11*width*slope1
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

    effectiveLevel:=MapControlToEffective(level)

    dark:=(500-effectiveLevel>0)?(500-effectiveLevel)/500.0:0.0
    bright:=(effectiveLevel-500>0)?(effectiveLevel-500)/500.0:0.0

    ; 保留原有、已经实际验证有效的视觉公式。
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
