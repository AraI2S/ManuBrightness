#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; ======================================================================================================================
; 软件亮度热键 - 重新映射版
;
; 版本背景：
;     实际使用一个月后发现，旧脚本中最常用的亮度值集中在 200 ~ 600。
;     为了让常用区间拥有更细的调节手感，本版不再把热键显示值直接用于 Gamma Ramp 公式，
;     而是先把“用户控制值”映射成“旧公式有效值”，再套用原来的 ApplyLevel 视觉曲线。
;
; 新映射目标：
;     新控制值 100  -> 旧视觉效果 200
;     新控制值 900  -> 旧视觉效果 600
;     新控制值 0    -> 旧视觉效果 0
;     新控制值 1000 -> 旧视觉效果 1000
;
; 实际效果：
;     旧版 200 ~ 600 这段日常常用范围，现在被摊开到新版 100 ~ 900。
;     原来每 25 一档时，200 ~ 600 只有约 17 个档位；现在 100 ~ 900 有约 33 个档位。
;     因此常用亮度段的微调会明显更细，极暗和极亮的少用区域会变得更粗。
;
; 注意：
;     本脚本显示/保存的是“新版控制值”，不是旧公式有效值。
;     例如新版 500 对应旧版约 400；旧版 500 对应新版约 700。
;
; 兼容旧 ini：
;     如果 GpuBrightness.ini 里没有 MapVersion，本脚本会把已有旧版 Level 自动迁移到新版控制值，
;     尽量避免第一次运行新版脚本时画面亮度突然跳变。
;
; 热键：
;     Alt + 数字小键盘 + ：增加软件亮度 stepSize
;     Alt + 数字小键盘 - ：降低软件亮度 stepSize
;     Alt + 数字小键盘 * ：刷新当前软件亮度，不改变数值
; ======================================================================================================================

global levelFile := A_ScriptDir "\GpuBrightness.ini"
global mapVersion := 2

global minLevel := 0
global maxLevel := 1000

global oldUsefulLow := 200
global oldUsefulHigh := 600
global newUsefulLow := 100
global newUsefulHigh := 900

global defaultLevel := 500
global stepSize := 25
global tipMs := 700

global level := LoadLevel()

ApplyLevel(level)

; 主热键：Alt + 小键盘 +/-，每次 ±stepSize
!NumpadAdd::Step(stepSize)
!NumpadSub::Step(-stepSize)

; 手动刷新当前软件亮度：Alt + 小键盘 *
!NumpadMult::RefreshLevel()

Step(delta){
    global level
    SetLevel(level+delta)
}

RefreshLevel(){
    global level
    ApplyLevel(level)
    ShowTip("软件亮度刷新: " level)
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
    global minLevel, maxLevel, oldUsefulLow, oldUsefulHigh, newUsefulLow, newUsefulHigh

    c:=ClampLevel(controlLevel)

    if c<=newUsefulLow{
        return Lerp(minLevel, oldUsefulLow, (c-minLevel)/(newUsefulLow-minLevel))
    }

    if c<=newUsefulHigh{
        return Lerp(oldUsefulLow, oldUsefulHigh, (c-newUsefulLow)/(newUsefulHigh-newUsefulLow))
    }

    return Lerp(oldUsefulHigh, maxLevel, (c-newUsefulHigh)/(maxLevel-newUsefulHigh))
}

MapEffectiveToControl(effectiveLevel){
    global minLevel, maxLevel, oldUsefulLow, oldUsefulHigh, newUsefulLow, newUsefulHigh

    e:=ClampLevel(effectiveLevel)

    if e<=oldUsefulLow{
        return Lerp(minLevel, newUsefulLow, (e-minLevel)/(oldUsefulLow-minLevel))
    }

    if e<=oldUsefulHigh{
        return Lerp(newUsefulLow, newUsefulHigh, (e-oldUsefulLow)/(oldUsefulHigh-oldUsefulLow))
    }

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

        NumPut("ushort", v, ramp, (i)*2)
        NumPut("ushort", v, ramp, (256+i)*2)
        NumPut("ushort", v, ramp, (512+i)*2)
    }

    DllCall("gdi32\SetDeviceGammaRamp", "ptr", hdc, "ptr", ramp)
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdc)
}
