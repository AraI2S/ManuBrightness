#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; ======================================================================================================================
; 脚本名称：
;     ManuBrightness v6.2 —— 双模式软件亮度 + Gamma Ramp 严格一致性守护
;
; 项目版本沿革与当前定位：
;     过去的稳定工作版：ManuBrightness v5.1 = Gamma Ramp 第五版映射、50 步长。
;     v6.0 = 保留 v5.1 日常算法 + 新增独立影视映射。
;     v6.1 = 每秒状态读取、按需恢复与低频兜底写入。
;     当前 v6.2 = 保留全部原有行为，将 Gamma Ramp 比较改为逐项严格一致。
;     原来的 MapVersion=5 是“日常控制值 -> 有效视觉值”的映射版本，
;     不等于程序版本。本版日常映射没有变化，因此 MapVersion 仍为 5。
;
; 两种模式：
;     日常：完全沿用上传的 v5.1 计算公式、控制值范围和每步 50 的行为。
;     影视：一条新的、连续平滑的像素曲线，优先展开阴影、约束高光、保留纯黑。
;     Alt + 主键盘 =：切换日常 / 影视。每个模式分别保存自己的控制数值。
;     启动时默认进入日常模式；影视首次使用时默认亮度 600。
;
; 影视模式设计基准（便于以后修改）：
;     在影视控制值 600 时，像素输入 5%、10%、20% 的输出约为
;     22%、32%、45%，接近日常控制值 800 的暗部效果；
;     而输入 80% 时输出约 89%，比日常控制值 600 更收敛。
;     纯黑 (0) 始终映射到 0；极深黑先接近原值，随后平滑过渡到提亮曲线。
;     影视曲线主要采用 y=x^filmGamma，无日常曲线的 gain 和 lift。
;     影视控制值变化只改变 filmGamma，曲线不发生局部断裂。
;
; 黑位保护：
;     对 0.3% 以下的输入基本保留原样，至 2.5% 平滑过渡完成。
;     这是视觉尝试参数，不是 MiniLED 硬件问题的解决方案。
;     如以后发现黑位被压得过狠，可适当降低 filmToeEnd；
;     如果暗灰仍然泛白，可适当提高 filmToeEnd。
;
; 配置存储：
;     新配置文件：ManuBrightness.ini（分别保存 DailyLevel / FilmLevel）。
;     首次运行可自动读取同目录下旧 GpuBrightness.ini 的日常亮度，
;     原文件保留不删除，以便随时回退老版本。
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
;     Alt + 主键盘 =     ：切换日常 / 影视模式
;
; Gamma Ramp 自动维护（v6.2）：
;     正常工作状态下每 1000 毫秒读取一次 GetDeviceGammaRamp，和当前模式的目标曲线比较。
;     一旦有任意 16 位参数不一致，立即重新应用当前曲线；不改变亮度值，不显示提示，也不写入 ini。
;     严格比较完整 3×256 项 Gamma Ramp：只要任意 ushort 不同，就认定参数不一致，不设置容差。
;     为防止驱动只返回缓存值、读数失败或报告过于粗略，每 30 次检查无条件重新写入一次。
;     用户手动按 Alt + 小键盘 / 暂停时：停止检查与所有自动写入；
;     下次 +/-、* 或切换模式后恢复检查。
;     原本的 SetDeviceGammaRamp API 在 HDR/驱动/色彩配置上的局限仍然存在，
;     因此这属于可靠性补强，不能保证屏幕每一种显示失常都能被探测到。
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

global appVersion := "6.2"
global levelFile := A_ScriptDir "\ManuBrightness.ini"
global oldLevelFile := A_ScriptDir "\GpuBrightness.ini"

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

; 影视模式曲线参数：在亮度 600 时 filmGamma=0.50。
; 越小越抬亮阴影；越大则越压暗。只用于影视模式。
global filmDefaultLevel := 600
global filmReferenceLevel := 600
global filmGammaAt600 := 0.50
global filmGammaSensitivity := 0.0035
global filmGammaMin := 0.12
global filmGammaMax := 4.0

; 黑位保护起点/终点（像素值已经归一化到 0..1）。
global filmToeStart := 0.003
global filmToeEnd := 0.025

; Gamma Ramp 自动维护：工作时每秒读取检查一次。
; 任意 16 位数值不一致时立即写回；保留每 30 秒兜底刷新。
global gammaWatchIntervalMs := 1000
; 30 次 × 1000ms = 约 30 秒。
global gammaWatchForceTicks := 30
; 当前是否由 Alt + 小键盘 / 临时暂停。
global gammaWatchPaused := false
; 记录目前应当生效的完整 3×256 项 Gamma Ramp。
global expectedGammaRamp := Buffer(256*3*2, 0)
global gammaWatchTicks := 0

; 默认进入日常，且两个模式分别记住自己的亮度。
global activeMode := "Daily"
global level := LoadLevel()
global dailyLevel := level
global filmLevel := LoadFilmLevel()

ApplyLevel(level)

; Alt + 小键盘 +/-：每次 ±stepSize
!NumpadAdd::Step(stepSize)
!NumpadSub::Step(-stepSize)

; Alt + 小键盘 *：重新应用当前软件亮度
!NumpadMult::RefreshLevel()

; Alt + 小键盘 /：临时恢复无脚本介入效果
!NumpadDiv::ResetGammaRamp()

; Alt + 主键盘 =：切换“日常 / 影视”模式（无需按 Shift）
!=::SwitchMode()

SwitchMode(){
    global activeMode, level, dailyLevel, filmLevel
    if activeMode="Daily"{
        dailyLevel:=level
        activeMode:="Film"
        level:=filmLevel
        modeLabel:="影视"
    } else {
        filmLevel:=level
        activeMode:="Daily"
        level:=dailyLevel
        modeLabel:="日常"
    }
    ApplyLevel(level)
    ShowTip("ManuBrightness " modeLabel ": " level)
}

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
    global gammaWatchPaused, gammaWatchTicks
    ; 先禁止未来的自动补写，再执行一次标准 Gamma Ramp 写入。
    gammaWatchPaused:=true
    gammaWatchTicks:=0
    SetTimer(CheckGammaRamp, 0)
    ApplyIdentityGammaRamp()
    ShowTip("软件亮度暂停")
}

SetLevel(v){
    global level, levelFile, mapVersion, activeMode, dailyLevel, filmLevel

    v:=RoundToStep(v)
    v:=ClampLevel(v)

    level:=v
    ApplyLevel(level)

    if activeMode="Daily"{
        dailyLevel:=level
        IniWrite(level, levelFile, "Modes", "DailyLevel")
        ; [Main] 保留旧脚本的数据结构，便于迁移与回溯。
        IniWrite(level, levelFile, "Main", "Level")
        IniWrite(mapVersion, levelFile, "Main", "MapVersion")
        modeLabel:="日常"
    } else {
        filmLevel:=level
        IniWrite(level, levelFile, "Modes", "FilmLevel")
        modeLabel:="影视"
    }

    ShowTip(modeLabel "亮度: " level)
}

LoadLevel(){
    global levelFile, oldLevelFile, mapVersion, defaultLevel

    ; 已使用过 v6 的独立日常亮度，优先直接读取。
    raw:=IniRead(levelFile, "Modes", "DailyLevel", "")
    if raw!=""{
        try {
            return ClampLevel(Float(raw))
        } catch {
            ; 无效数值则继续尝试原版数据。
        }
    }

    ; 兼容新文件的 [Main]，然后尝试同目录的旧 GpuBrightness.ini。
    sourceFile:=levelFile
    raw:=IniRead(sourceFile, "Main", "Level", "")
    if raw=""{
        sourceFile:=oldLevelFile
        raw:=IniRead(sourceFile, "Main", "Level", "")
    }

    if raw=""{
        return ClampLevel(defaultLevel)
    }

    try v:=Float(raw)
    catch
        v:=defaultLevel

    storedVersion:=IniRead(sourceFile, "Main", "MapVersion", "1")

    ; 按旧脚本的既有公式迁移（包括旧版 V1..V4）。
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
    } else if storedVersion!=String(mapVersion){
        v:=defaultLevel
    }

    ; 已是 V5 时保持原始数值；需要迁移时才按原工作版的规则对齐步长。
    if storedVersion!=String(mapVersion){
        v:=RoundToStep(v)
    }
    v:=ClampLevel(v)

    ; 新文件独立保存；不会修改旧 GpuBrightness.ini。
    IniWrite(v, levelFile, "Modes", "DailyLevel")
    IniWrite(v, levelFile, "Main", "Level")
    IniWrite(mapVersion, levelFile, "Main", "MapVersion")

    return v
}

LoadFilmLevel(){
    global levelFile, filmDefaultLevel
    raw:=IniRead(levelFile, "Modes", "FilmLevel", "")
    if raw=""
        return filmDefaultLevel
    try {
        return ClampLevel(Float(raw))
    } catch {
        return filmDefaultLevel
    }
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
    global activeMode, gammaWatchPaused, gammaWatchTicks, gammaWatchIntervalMs
    ; 四个能够恢复工作的操作，都通过这里重新启用自动维护。
    gammaWatchPaused:=false
    gammaWatchTicks:=0
    if activeMode="Film"
        ApplyFilmLevel(level)
    else
        ApplyDailyLevel(level)
    SetTimer(CheckGammaRamp, gammaWatchIntervalMs)
}

; 每秒严格比较实际 Gamma Ramp：任意一个 16 位值不一致即重新写入。
CheckGammaRamp(){
    global gammaWatchPaused, gammaWatchTicks, gammaWatchForceTicks
    global expectedGammaRamp, level
    if gammaWatchPaused
        return

    gammaWatchTicks+=1

    ; GetDeviceGammaRamp 有时只是驱动缓存的结果，因此定期强制补写一次。
    if gammaWatchTicks>=gammaWatchForceTicks{
        ApplyLevel(level)
        return
    }

    hdc:=DllCall("GetDC", "ptr", 0, "ptr")
    if !hdc
        return

    currentRamp:=Buffer(256*3*2, 0)
    success:=DllCall("gdi32\GetDeviceGammaRamp", "ptr", hdc, "ptr", currentRamp, "int")
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdc)

    ; 读取失败时不每秒盲写；30 秒兜底仍然有效。
    if !success
        return

    ; 三个通道各 256 个 WORD，逐项严格比较；任意差异都触发修复。
    Loop 768 {
        offset:=(A_Index-1)*2
        observed:=NumGet(currentRamp, offset, "ushort")
        desired:=NumGet(expectedGammaRamp, offset, "ushort")
        if observed!=desired{
            ApplyLevel(level)
            return
        }
    }
}

; 日常版本沿用之前的完整 Gamma Ramp 公式和输入控制映射。
ApplyDailyLevel(level){
    global expectedGammaRamp
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

    ; 保存当前模式实际希望维持的曲线，供下一秒检测。
    expectedGammaRamp:=ramp
    DllCall("gdi32\SetDeviceGammaRamp", "ptr", hdc, "ptr", ramp)
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdc)
}

; ----------------------------------------------------------------------------------------------------------------------
; 影视模式：保黑位、展暗部、收高光。
;     y = x^filmGamma（无 gain / lift）
;     对极深黑区域逐渐从恒等映射过渡到以上曲线，避免纯黑或近黑泛灰。
; ----------------------------------------------------------------------------------------------------------------------
ApplyFilmLevel(level){
    global expectedGammaRamp
    global filmReferenceLevel, filmGammaAt600, filmGammaSensitivity
    global filmGammaMin, filmGammaMax, filmToeStart, filmToeEnd

    gamma:=filmGammaAt600 * Exp((filmReferenceLevel-level)*filmGammaSensitivity)
    gamma:=Max(filmGammaMin, Min(filmGammaMax, gamma))

    hdc:=DllCall("GetDC", "ptr", 0, "ptr")
    ramp:=Buffer(256*3*2, 0)

    Loop 256{
        i:=A_Index-1
        x:=i/255.0

        boosted:=x**gamma

        if gamma<1{
            ; 平滑保护最深黑。0..0.3% 基本不动，2.5% 起完整应用提亮曲线。
            t:=(x-filmToeStart)/(filmToeEnd-filmToeStart)
            t:=Max(0,Min(1,t))
            weight:=t*t*(3-2*t)
            y:=x+(boosted-x)*weight
        } else {
            ; 暗化时直接使用幂次曲线，黑位天然为 0。
            y:=boosted
        }

        y:=Max(0,Min(1,y))
        v:=Round(y*65535)

        NumPut("ushort", v, ramp, i*2)
        NumPut("ushort", v, ramp, (256+i)*2)
        NumPut("ushort", v, ramp, (512+i)*2)
    }

    ; 保存当前模式实际希望维持的曲线，供下一秒检测。
    expectedGammaRamp:=ramp
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
