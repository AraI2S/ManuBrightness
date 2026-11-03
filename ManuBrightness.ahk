#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

global levelFile := A_ScriptDir "\GpuBrightness.ini"
global stepSize := 25
global level := LoadLevel()

ApplyLevel(level)

; 主热键：Alt + 小键盘 +/-，每次 ±stepSize
!NumpadAdd::Step(stepSize)
!NumpadSub::Step(-stepSize)

Step(delta){
    global level
    SetLevel(level+delta)
}

SetLevel(v){
    global level, levelFile, stepSize
    v:=Round(v/stepSize)*stepSize
    if v<0
        v:=0
    if v>1000
        v:=1000
    level:=v
    ApplyLevel(level)
    IniWrite(level, levelFile, "Main", "Level")
    ShowTip("软件亮度: " level)
}

LoadLevel(){
    global levelFile
    try v:=Integer(IniRead(levelFile, "Main", "Level", "500"))
    catch
        v:=500
    if v<0
        v:=0
    if v>1000
        v:=1000
    return v
}

ShowTip(txt){
    ToolTip(txt)
    SetTimer(ClearTip, -700)
}

ClearTip(){
    ToolTip()
}

ApplyLevel(level){
    hdc:=DllCall("GetDC", "ptr", 0, "ptr")
    ramp:=Buffer(256*3*2, 0)

    dark:=(500-level>0)?(500-level)/500.0:0.0
    bright:=(level-500>0)?(level-500)/500.0:0.0

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

        NumPut("ushort", v, ramp, (i)*2)
        NumPut("ushort", v, ramp, (256+i)*2)
        NumPut("ushort", v, ramp, (512+i)*2)
    }

    DllCall("gdi32\SetDeviceGammaRamp", "ptr", hdc, "ptr", ramp)
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdc)
}

; ======================================================================================================================
; 脚本名称：
;     软件亮度热键（基于 Windows Gamma Ramp 的桌面输出层亮度调节）
;
; 这份脚本是为如下具体使用场景而写：
;     用户使用 MSI Titan 18 Pro 2024 笔记本，搭载 RTX 4070 Laptop 显卡与 4K MiniLED 内屏。
;     这块屏幕的实际亮度能力跨度极大，但 Windows 自带的系统亮度滑条可调范围不够用：
;         1. 有时最低亮度仍然太亮；
;         2. 有时最高亮度仍然不够亮；
;         3. 用户的日常工作会频繁在“很暗”和“很亮”之间快速切换。
;
; 原始工作流：
;     过去用户主要通过 NVIDIA 控制面板：
;         “显示” -> “调整桌面颜色设置” -> “应用色彩增强” -> “亮度”
;     来手动改变桌面整体观感亮度。
;     这种方法本质上不是单纯修改 Windows 系统亮度条，也不是单纯修改面板物理背光，
;     而更接近于在显卡/桌面输出层面对整体亮度观感进行重新映射。
;
; 原始问题：
;     虽然 NVIDIA 控制面板里的方法有效，但每次都要：
;         打开控制面板 -> 等待界面载入 -> 进入对应页面 -> 手动拖动滑条 -> 点击应用
;     对于高频使用来说非常麻烦。
;
; 这个脚本的目标：
;     用两个热键，快速替代那种“打开 NVIDIA 控制面板手动拖亮度”的繁琐流程。
;     期望用法是：
;         - 先把 Windows 自带系统亮度固定在某个中间值（例如 50% 左右）；
;         - 之后基本不再频繁改系统亮度；
;         - 改为只使用本脚本的热键，在更大的主观亮度范围内快速上下调节。
;
; 目前绑定的热键：
;     Alt + 数字小键盘 +
;         -> 增加软件亮度 stepSize
;     Alt + 数字小键盘 -
;         -> 降低软件亮度 stepSize
;
; 数值设计：
;     本脚本把“软件亮度”抽象为一个 0 ~ 1000 的内部标尺。
;     其中：
;         500 = 中性基准状态
;         小于 500 = 逐渐变暗
;         大于 500 = 逐渐变亮
;     这个数值不是 Windows 亮度百分比，也不是显示器真实 nits，只是本脚本内部使用的控制标尺。
;
; 步长设计：
;     stepSize 是唯一的热键步长常量。
;     当前设为 25。
;     以后如果想改成每次 ±10、±20、±50，只需要修改开头这一个常量，不用改别处逻辑。
;
; 工作原理：
;     本脚本调用 Windows 的 SetDeviceGammaRamp API，修改整个桌面输出的 Gamma Ramp。
;     简单理解，就是对送往屏幕的图像信号做一次整体映射，从而改变“看起来有多亮/多暗”。
;     它不是：
;         - 直接调笔记本面板背光；
;         - 直接调用 NVIDIA 控制面板内部私有接口；
;         - 直接同步修改 NVIDIA 控制面板中显示的亮度数值。
;
; 因此应这样理解它：
;     这不是“物理亮度热键”，而是“软件亮度热键”。
;     它非常适合拿来替代“频繁手动调 NVIDIA 控制面板桌面亮度”的工作流。
;
; 参数说明：
;     脚本内部主要通过三个量控制亮度观感：
;         gamma  -> 影响整体明暗分布曲线
;         gain   -> 影响整体增益
;         lift   -> 在高亮时适度抬升暗部，增强“更亮”的体感
;     这些参数是为当前设备和主观使用需求调出来的一组经验值。
;     如果未来觉得：
;         - 变暗不够狠
;         - 变亮不够猛
;         - 暗部压得太死
;         - 高亮时发灰
;     可以继续微调这三组公式。
;
; 持久化保存：
;     当前亮度值会保存到脚本所在目录下的 GpuBrightness.ini。
;     这样脚本下次启动时，会自动恢复上次使用的亮度，而不是每次都从 500 开始。
;
; 为什么文件名叫 GpuBrightness.ini：
;     这是沿用本任务最初语境的命名，方便记忆它是在“显卡层亮度替代方案”背景下写出来的。
;     虽然严格说它并不是直接调用 GPU 私有亮度接口，而是通过 Windows 图形输出层实现。
;
; 已知局限性与注意事项：
;     1. 某些程序、驱动事件、分辨率变化、显示模式切换、HDR 开关、色彩管理软件、远程桌面、
;        或显卡驱动重置，有可能覆盖或重置当前 Gamma Ramp。
;     2. 如果发生了“突然看起来失效”的情况，通常不代表脚本坏了，可能只是系统把 Gamma Ramp 重置了；
;        这时重新按一次热键，或重新运行脚本，通常即可恢复。
;     3. 由于这是全局桌面输出映射，它影响的是整个桌面观感，不是只影响单个软件。
;     4. 它和 NVIDIA 控制面板中的视觉效果会相似，但不保证逐点完全一致。
;
; 推荐使用方式：
;     1. Windows 自带亮度固定在一个你认为舒适的中间值；
;     2. 日常只用 Alt + 小键盘 +/- 做大范围快速切换；
;     3. 若想开机自动生效，可把本脚本或其快捷方式放入 shell:startup。
;
; 未来可能继续优化的方向：
;     1. 增加屏幕右下角更明显的 OSD 显示；
;     2. 增加托盘菜单，手动选择几个常用档位；
;     3. 增加“一键恢复 500 中性值”热键；
;     4. 把默认初始值、上下限、提示持续时间也提取成开头常量；
;     5. 为不同使用场景提供不同参数曲线，例如“夜间极暗模式”“日光高亮模式”。
;
; 当前版本保留的最核心设计原则：
;     尽量少热键、尽量少配置、尽量高频好用。
;     所以目前只保留两个最核心热键，不再保留 F1/F2/F3 等预设键。
; ======================================================================================================================