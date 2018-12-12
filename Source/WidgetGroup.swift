import Cocoa

protocol WGDelegate {
    func wgCommand(_ ident:WgIdent)
    func wgToggle(_ ident:WgIdent)
    func wgGetString(_ ident:WgIdent) -> String
    func wgGetColor(_ ident:WgIdent) -> NSColor
    func wgOptionSelected(_ ident:WgIdent, _ index:Int)
    func wgGetOptionString(_ ident:WgIdent) -> String
}

enum WgEntryKind { case singleFloat,dualFloat,dropDown,option,command,toggle,legend,line,string,color,gap,float3Dual,float3Single,float3xy,float3z, move,zoom }
enum WgIdent { case none,resolution,saveLoad,loadNext,reset,help,coloring,chicken,shadow,pt0,pt1,pt2,lt0,lt1,lt2,foam,variation }

let wgBackgroundColor = NSColor(red:0.1, green:0.02, blue:0.02, alpha: 1)
let wgHighlightColor = NSColor(red:0.4, green:0.2, blue:0, alpha:1)
let wgMorphColor = NSColor(red:0.1, green:0.1, blue:0.6, alpha:1)

let NONE:Int = -1
let FontSZ:CGFloat = 15
let RowHT:CGFloat = FontSZ + 4
let GrphSZ:CGFloat = RowHT - 4
let TxtYoff:CGFloat = -3
let Tab0:CGFloat = 5     // hotKey
let Tab1:CGFloat = 5+20     // graph x1
let Tab2:CGFloat = 18+20    // text after graph
let Tab3:CGFloat = Tab2 + GrphSZ + 3 // text after 2 graphs
var py = CGFloat()

struct wgEntryData {
    var hotKey:String = ""
    var kind:WgEntryKind = .legend
    var ident:WgIdent = .none
    var morph:Bool = false
    var str:[String] = []
    var valuePointerX:UnsafeMutableRawPointer! = nil
    var valuePointerY:UnsafeMutableRawPointer! = nil
    var deltaValue:Float = 0
    var mRange = float2()
    var visible:Bool = true
    var yCoord = CGFloat()
    
    func isValueWidget() ->Bool { return kind == .singleFloat || kind == .dualFloat }
    
    func getFloatValue(_ who:Int) -> Float {
        switch who {
        case 0 :
            if valuePointerX == nil { return 0 }
            return valuePointerX.load(as: Float.self)
        default:
            if valuePointerY == nil { return 0 }
            return valuePointerY.load(as: Float.self)
        }
    }
    
    func getInt32Value() -> Int {
        if valuePointerX == nil { return 0 }
        let v =  Int(valuePointerX.load(as: Int32.self))
        //Swift.print("getInt32Value = ",v.description)
        return v
    }
    
    func ratioClamped(_ v:CGFloat) -> CGFloat {
        if v < 0.05 { return CGFloat(0.05) }          // so graph line is always visible
        if v > 0.95 { return CGFloat(0.95) }
        return v
    }
    
    func valueRatio(_ who:Int) -> CGFloat {
        let den = mRange.y - mRange.x
        if den == 0 { return CGFloat(0) }
        return ratioClamped(CGFloat((getFloatValue(who) - mRange.x) / den ))
    }
    
    func float3ValueRatio(_ who:Int) -> CGFloat {
        func getFloat3Value(_ who:Int) -> Float {
            if valuePointerX == nil { return 0 }
            let v:float3 = valuePointerX.load(as: float3.self)
            switch who {
            case 0 : return v.x
            case 1 : return v.y
            case 2 : return v.z
            default: return 0
            }
        }
        
        let den = mRange.y - mRange.x
        if den == 0 { return CGFloat(0) }
        return ratioClamped(CGFloat((getFloat3Value(who) - mRange.x) / den ))
    }
}

class WidgetGroup: NSView {
    var delegate:WGDelegate?
    var context : CGContext?
    var data:[wgEntryData] = []
    var focus:Int = NONE
    var previousFocus:Int = NONE
    var delta = float3()
    let color = NSColor.lightGray
    
    func reset() { data.removeAll() }
    func hasFocus() -> Bool { return focus != NONE }
    func removeAllFocus() { focus = NONE; refresh() }
    func refresh() { setNeedsDisplay(bounds) }
    override var isFlipped: Bool { return true }
    
    func wgOptionSelected(_ ident:WgIdent, _ index:Int) {
        delegate?.wgOptionSelected(ident,index)
        refresh()
    }
    
    //MARK: -
    
    func hotKey(_ s:String) {
        if s.count == 0 { return }
        
        for i in 0 ..< data.count {
            if s == data[i].hotKey {
                switch data[i].kind {
                case .command :
                    delegate?.wgCommand(data[i].ident)
                case .toggle : delegate?.wgToggle(data[i].ident)
                default : focus = i
                }

                refresh()
                return
            }
        }
    }
    
    func togglealterValueViaMorph() {
        if focus != NONE {
            data[focus].morph = !data[focus].morph
            refresh()
        }
    }

    //MARK:-
    
    func morphReset() {
        for i in 0 ..< data.count {
            data[i].morph = false
        }
    }
    
    func alterValueViaMorph(_ index:Int, _ ratio:Float) -> Bool {
        func morphFloat3Value() -> float3 { return data[index].valuePointerX.load(as: float3.self) }
        
        if !data[index].morph { return false }
        
        let amt = ratio * data[index].deltaValue / 20
        
        switch(data[index].kind) {
        case .singleFloat :
            let valueX = fClamp2(data[index].getFloatValue(0) + amt, data[index].mRange)
            data[index].valuePointerX.storeBytes(of:valueX, as:Float.self)
            
            if data[index].kind == .dualFloat {
                let valueY = fClamp2(data[index].getFloatValue(1) + amt, data[index].mRange)
                data[index].valuePointerY.storeBytes(of:valueY, as:Float.self)
            }
        case .float3Dual, .float3xy, .float3z :  // alter all fields of float3
            var v:float3 = morphFloat3Value()
            v.x = fClamp2(v.x + amt, data[index].mRange)
            v.y = fClamp2(v.y + amt, data[index].mRange)
            v.z = fClamp2(v.z + amt, data[index].mRange)
            data[index].valuePointerX.storeBytes(of:v, as:float3.self)
        default : break
        }

        return true
    }

    //MARK:-
    
    var dIndex:Int = 0
    
    func newEntry(_ hotKey:String, _ nKind:WgEntryKind) {
        data.append(wgEntryData())
        dIndex = data.count-1
        
        data[dIndex].hotKey = hotKey
        data[dIndex].kind = nKind
    }
    
    func addCommon(_ ddIndex:Int, _ min:Float, _ max:Float, _ delta:Float, _ iname:String) {
        data[ddIndex].mRange.x = min
        data[ddIndex].mRange.y = max
        data[ddIndex].deltaValue = delta
        data[ddIndex].str.append(iname)
    }
    
    func addSingleFloat(_ hotKey:String, _ vx:UnsafeMutableRawPointer, _ min:Float, _ max:Float,  _ delta:Float, _ iname:String) {
        newEntry(hotKey,.singleFloat)
        data[dIndex].valuePointerX = vx
        addCommon(dIndex,min,max,delta,iname)
    }
    
    func addDualFloat(_ hotKey:String, _ vx:UnsafeMutableRawPointer, _ vy:UnsafeMutableRawPointer, _ min:Float, _ max:Float,  _ delta:Float, _ iname:String) {
        newEntry(hotKey,.dualFloat)
        data[dIndex].valuePointerX = vx
        data[dIndex].valuePointerY = vy
        addCommon(dIndex,min,max,delta,iname)
    }
    
    //MARK:-
    
    func addFloat3Dual(_ hotKey:String, _ vx:UnsafeMutableRawPointer, _ min:Float, _ max:Float,  _ delta:Float, _ iname:String) {
        newEntry(hotKey,.float3Dual)
        data[dIndex].valuePointerX = vx
        addCommon(dIndex,min,max,delta,iname)
    }
    
    func addFloat3Single(_ hotKey:String, _ vx:UnsafeMutableRawPointer, _ min:Float, _ max:Float,  _ delta:Float, _ iname:String) {
        newEntry(hotKey,.float3Single)
        data[dIndex].valuePointerX = vx
        addCommon(dIndex,min,max,delta,iname)
    }
    
    func addTriplet(_ hotKey:String, _ vx:UnsafeMutableRawPointer, _ min:Float, _ max:Float,  _ delta:Float, _ iname:String) {
        newEntry(hotKey,.float3xy)
        data[dIndex].valuePointerX = vx
        addCommon(dIndex,min,max,delta,iname)
        
        newEntry("",.float3z)
        data[dIndex].valuePointerX = vx
        addCommon(dIndex,min,max,delta,"")
    }
    
    //MARK:-
    
    func addDropDown(_ hotKey:String, _ vx:UnsafeMutableRawPointer, _ items:[String]) {
        newEntry(hotKey,.dropDown)
        data[dIndex].valuePointerX = vx
        for i in items { data[dIndex].str.append(i) }
    }
    
    func addLegend(_ iname:String) {
        newEntry("",.legend)
        data[dIndex].str.append(iname)
    }
    
    func addToggle(_ hotKey:String,_ ident:WgIdent) {
        newEntry(hotKey,.toggle)
        data[dIndex].ident = ident
    }
    
    func addLine() {
        newEntry("",.line)
    }
    
    func addCommand(_ hotKey:String, _ iname:String, _ ident:WgIdent) {
        newEntry(hotKey,.command)
        data[dIndex].str.append(iname)
        data[dIndex].ident = ident
    }
    
    func addColoredCommand(_ hotKey:String, _ nCmd:WgIdent, _ legend:String) {
        addColor(nCmd,Float(RowHT))
        addCommand(hotKey,legend,nCmd)
    }
    
    func addString(_ iname:String, _ cNumber:WgIdent) {
        newEntry("",.string)
        data[dIndex].str.append(iname)
        data[dIndex].ident = cNumber
    }
    
    func addColor(_ index:WgIdent, _ height:Float) {
        newEntry("",.color)
        data[dIndex].ident = index
        data[dIndex].deltaValue = height
    }
    
    func addOptionSelect(_ ident:WgIdent, _ title:String, _ message:String, _ options:[String]) {
        newEntry("",.option)
        data[dIndex].ident = ident
        data[dIndex].str.append(title)
        data[dIndex].str.append(message)
        for i in 0 ..< options.count { data[dIndex].str.append(options[i]) }
    }
    
    func addGap(_ height:Float) {
        newEntry("",.gap)
        data[dIndex].deltaValue = height
    }
    
    //MARK:-
    
    func drawGraph(_ index:Int) {
        let d = data[index]
        let x:CGFloat = d.kind == .float3z ? 28 + GrphSZ : 25
        let rect = CGRect(x:x, y:py, width:GrphSZ, height:GrphSZ)
        
        NSColor.black.set()
        NSBezierPath(rect:rect).fill()
        
        context!.setLineWidth(2)
        let tColor:NSColor = index == focus ? .green : color
        tColor.set()
        
        switch d.kind {
        case .float3Dual, .float3xy :
            let cx = rect.origin.x + d.float3ValueRatio(0) * rect.width
            drawVLine(context!,cx,rect.origin.y,rect.origin.y + GrphSZ)
            
            let y = rect.origin.y + (1.0 - d.float3ValueRatio(1)) * rect.height
            drawHLine(context!,rect.origin.x,rect.origin.x + GrphSZ,y)
        case .float3z :
            if focus == index-1 { NSColor.green.set() }
            let cx = rect.origin.x + d.float3ValueRatio(2) * rect.width
            drawVLine(context!,cx,rect.origin.y,rect.origin.y + GrphSZ)
        default :
            let cx = rect.origin.x + d.valueRatio(0) * rect.width
            drawVLine(context!,cx,rect.origin.y,rect.origin.y + GrphSZ)
            
            if d.kind == .dualFloat || d.kind == .float3Dual || d.kind == .float3xy {
                let y = rect.origin.y + (1.0 - d.valueRatio(1)) * rect.height
                drawHLine(context!,rect.origin.x,rect.origin.x + GrphSZ,y)
            }
        }
        
        NSBezierPath(rect:rect).stroke()
        
        let tab = data[index].kind == .float3xy ? Tab3+10 : Tab2+10
        drawText(tab,py+TxtYoff,tColor,FontSZ,data[index].str[0])
    }
    
    func drawEntry(_ index:Int) {
        let tColor:NSColor = index == focus ? .green : color
        data[index].yCoord = py
        
        drawText(Tab0,py+TxtYoff,tColor,FontSZ,data[index].hotKey)
        
        switch(data[index].kind) {
        case .singleFloat, .dualFloat, .float3Dual, .float3Single, .float3xy, .float3z, .move, .zoom : drawGraph(index)
        case .dropDown : drawText(Tab1,py+TxtYoff,tColor,FontSZ,data[index].str[data[index].getInt32Value()])
        case .command  : drawText(Tab1,py+TxtYoff,tColor,FontSZ,data[index].str[0])
        case .string   : drawText(Tab1,py+TxtYoff,tColor,FontSZ, (delegate?.wgGetString(data[index].ident))!)
        case .toggle   : drawText(Tab1,py+TxtYoff,tColor,FontSZ, (delegate?.wgGetString(data[index].ident))!)
        case .legend   : drawText(Tab1,py+TxtYoff,.yellow,FontSZ,data[index].str[0])
        case .option   : drawText(Tab1,py+TxtYoff,tColor,FontSZ, (delegate?.wgGetOptionString(data[index].ident))!)
            
        case .line :
            color.set()
            context?.setLineWidth(1)
            drawHLine(context!,0,bounds.width,py)
            py -= RowHT - 5
            
        case .color :
            let c = (delegate?.wgGetColor(data[index].ident))!
            c.setFill()
            let r = CGRect(x:1, y:py-3, width:bounds.width-2, height:CGFloat(data[index].deltaValue)+2)
            NSBezierPath(rect:r).fill()
            py -= RowHT
            
        case .gap :
            py += CGFloat(data[index].deltaValue)
        }
        
        if data[index].kind != .float3xy { py += RowHT }
    }
    
    func baseYCoord() -> CGFloat { return 10 }
    
    override func draw(_ rect: CGRect) {
        g.setContext(NSGraphicsContext.current!)
        g.fillRect(bounds,NSColor.black.cgColor)
        g.lineWidth(2)
        g.drawBorder(bounds)
        
        if vc == nil { return }
        context = NSGraphicsContext.current?.cgContext
        
        wgBackgroundColor.setFill()
        NSBezierPath(rect:bounds).fill()
        
        py = baseYCoord()
        for i in 0 ..< data.count { drawEntry(i) }
        
        color.setStroke()
        NSBezierPath(rect:bounds).stroke()
    }
    
    func nextYCoord() -> CGFloat {
        py = baseYCoord()
        for i in 0 ..< data.count {
            switch(data[i].kind) {
            case .line  : py -= RowHT - 5
            case .color : py -= RowHT
            case .gap   : py += CGFloat(data[i].deltaValue)
            default : break
            }
            
            py += RowHT
        }
        
        return py
    }
    
    //MARK:-
    
    func float3Value() -> float3 {
        if focus == NONE { return float3() }
        return data[focus].valuePointerX.load(as: float3.self)
    }
    
    func update() -> Bool {
        if focus == NONE { return false }
        if delta == float3() { return false } // marks end of session
        
        switch data[focus].kind {
        case .float3Dual :
            var v:float3 = float3Value()
            v.x = fClamp2(v.x + delta.x * data[focus].deltaValue, data[focus].mRange)
            v.y = fClamp2(v.y + delta.y * data[focus].deltaValue, data[focus].mRange)
            data[focus].valuePointerX.storeBytes(of:v, as:float3.self)
        case .float3xy, .float3z :
            var v:float3 = float3Value()
            
            if vc.shiftKeyDown { // Z = X, X = 0
                v.y = fClamp2(v.y + delta.y * data[focus].deltaValue, data[focus].mRange)
                v.z = fClamp2(v.z + delta.x * data[focus].deltaValue, data[focus].mRange)
            }
            else {
            v.x = fClamp2(v.x + delta.x * data[focus].deltaValue, data[focus].mRange)
            v.y = fClamp2(v.y + delta.y * data[focus].deltaValue, data[focus].mRange)
            }
            data[focus].valuePointerX.storeBytes(of:v, as:float3.self)
        default :
            if data[focus].isValueWidget() {
                let valueX = fClamp2(data[focus].getFloatValue(0) + delta.x * data[focus].deltaValue, data[focus].mRange)
                data[focus].valuePointerX.storeBytes(of:valueX, as:Float.self)
                
                if data[focus].kind == .dualFloat {
                    let valueY = fClamp2(data[focus].getFloatValue(1) + delta.y * data[focus].deltaValue, data[focus].mRange)
                    data[focus].valuePointerY.storeBytes(of:valueY, as:Float.self)
                }
            }
            else { return false }
        }
        
        delegate?.wgCommand(data[focus].ident)
        refresh()
        return true
    }
    
    func moveFocus(_ dir:Int) {
        if focus == NONE || data.count < 2 { return }
        
        func move() {
            while true {
                focus += dir
                if focus >= data.count { focus = 0 } else if focus < 0 { focus = data.count-1 }
                if [ .singleFloat, .dualFloat, .float3Dual, .float3Single, .float3xy, .float3z, .move, .zoom ].contains(data[focus].kind) { break }
            }
        }
        
        move()
        if data[focus].kind == .float3z { move() } // hop past the .z widget of float3() group
        
        refresh()
    }
    
    //MARK:-
    
    func stopChanges() { delta = float3() }
    
    func focusMovement(_ pt:CGPoint, _ touchCount:Int) {
        if focus == NONE { return }
        
        if touchCount == 0 { // panning just ended
            stopChanges()
            return
        }
        
        delta.x =  Float(pt.x) * 0.05
        delta.y = -Float(pt.y) * 0.05
        
        if data[focus].kind == .singleFloat { // largest delta runs the show
            if abs(delta.y) > abs(delta.x) { delta.x = delta.y }
        }
        
        refresh()
    }
    
    func hopValue(_ dx:Int, _ dy:Int) {
        if focus == NONE { return }
        delta.x = Float(dx)
        delta.y = Float(dy)
        delta.z = 0
        
        if vc.optionKeyDown { delta *= 3 } else if vc.letterAKeyDown { delta *= 0.1 }
    }
    
    //MARK:-
    
    func shouldMemorizeFocus(_ index:Int) -> Bool {
        if index == NONE { return false }
        return [ .singleFloat, .dualFloat, .command, .toggle, .option, .dropDown, .float3Dual, .float3Single, .float3xy, .float3z, .move, .zoom ].contains(data[index].kind)
    }
    
    var pt = NSPoint()
    
    func flippedYCoord(_ pt:NSPoint) -> NSPoint {
        var npt = pt
        npt.y = bounds.size.height - pt.y
        return npt
    }
    
    override func mouseDown(with event: NSEvent) {
        pt = flippedYCoord(event.locationInWindow)
        
        stopChanges()
        if shouldMemorizeFocus(focus) { previousFocus = focus }

        for i in 0 ..< data.count { // move Focus to this entry?
            if pt.y >= data[i].yCoord && pt.y < data[i].yCoord + RowHT && shouldMemorizeFocus(i) {
                focus = i
                break
            }
        }
        
        if focus != NONE {
            if data[focus].kind == .command {
                delegate?.wgCommand(data[focus].ident)

                switch data[focus].ident {
                default :
                    focus = NONE
                    if previousFocus != NONE { focus = previousFocus }
                }
                
                refresh()
                return
            }
            
            if data[focus].kind == .toggle {
                delegate?.wgToggle(data[focus].ident)
                
                focus = NONE
                if previousFocus != NONE { focus = previousFocus }
                
                refresh()
                return
            }
        }
        
        refresh()
        stopChanges()
    }
    
    func fClamp2(_ v:Float, _ range:float2) -> Float {
        if v < range.x { return range.x }
        if v > range.y { return range.y }
        return v
    }
}

// MARK:

func drawLine(_ context:CGContext, _ p1:CGPoint, _ p2:CGPoint) {
    context.beginPath()
    context.move(to:p1)
    context.addLine(to:p2)
    context.strokePath()
}

func drawVLine(_ context:CGContext, _ x:CGFloat, _ y1:CGFloat, _ y2:CGFloat) { drawLine(context,CGPoint(x:x,y:y1),CGPoint(x:x,y:y2)) }
func drawHLine(_ context:CGContext, _ x1:CGFloat, _ x2:CGFloat, _ y:CGFloat) { drawLine(context,CGPoint(x:x1, y:y),CGPoint(x: x2, y:y)) }

func drawRect(_ context:CGContext, _ r:CGRect) {
    context.beginPath()
    context.addRect(r)
    context.strokePath()
}

func drawFilledCircle(_ context:CGContext, _ center:CGPoint, _ diameter:CGFloat, _ color:CGColor) {
    context.beginPath()
    context.addEllipse(in: CGRect(x:CGFloat(center.x - diameter/2), y:CGFloat(center.y - diameter/2), width:CGFloat(diameter), height:CGFloat(diameter)))
    context.setFillColor(color)
    context.fillPath()
}

//MARK:-

var fntSize:CGFloat = 0
var txtColor:NSColor = .clear
var textFontAttributes:NSDictionary! = nil

func drawText(_ x:CGFloat, _ y:CGFloat, _ color:NSColor, _ sz:CGFloat, _ str:String) {
    if str.count == 0 { return }
    
    if sz != fntSize || color != txtColor {
        fntSize = sz
        txtColor = color
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.alignment = NSTextAlignment.left
        let font = NSFont.init(name: "Helvetica", size:sz)!
        
        textFontAttributes = [
            NSAttributedString.Key.font: font,
            NSAttributedString.Key.foregroundColor: color,
            NSAttributedString.Key.paragraphStyle: paraStyle,
        ]
    }
    
    str.draw(in: CGRect(x:x, y:y, width:800, height:100), withAttributes: textFontAttributes as? [NSAttributedString.Key : Any])
}
