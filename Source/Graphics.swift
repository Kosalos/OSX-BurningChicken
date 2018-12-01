import Cocoa

let colorWhite = NSColor(red:1, green:1, blue:1, alpha:1).cgColor
let colorYellow = NSColor(red:1, green:1, blue:0, alpha:1).cgColor
let colorBlue = NSColor(red:0, green:0.3, blue:1, alpha:1).cgColor
let colorRed = NSColor(red:0.75, green:0.1, blue:0, alpha:1).cgColor
let colorGreen = NSColor(red:0, green:0.75, blue:0, alpha:1).cgColor
let colorBlack = NSColor(red:0, green:0, blue:0, alpha:1).cgColor
let colorRedTint = NSColor(red:0.2, green:0.1, blue:0.1, alpha:1).cgColor
let colorGreenTint = NSColor(red:0, green:0.2, blue:0, alpha:1).cgColor

let colorGray1 = NSColor(red:0.1, green:0.1, blue:0.1, alpha:1).cgColor
let colorGray2 = NSColor(red:0.4, green:0.4, blue:0.4, alpha:1).cgColor
let colorGray3 = NSColor(red:0.7, green:0.7, blue:0.7, alpha:1).cgColor

let font = NSFont.init(name: "Helvetica", size: 10)!

enum StringXJustify { case left,center,right }
enum StringYJustify { case top,center,bottom }

class Graphics {
    var context:CGContext!
    var stringXJ:StringXJustify = .left
    var stringYJ:StringYJustify = .center
    var stringFontSize:CGFloat = 16
    var stringColor:NSColor = .white
    var stringFont:NSFont!
    var stringAtts:[NSAttributedString.Key : Any]!

    func setContext(_ c:NSGraphicsContext) { context = c.cgContext }
    
    func lineWidth(_ w:CGFloat) { context.setLineWidth(w) }
    
    func stringPrepare() {
        stringFont = NSFont.init(name: "Helvetica", size:CGFloat(stringFontSize))!
        
        stringAtts = [
            NSAttributedString.Key.font:stringFont,
            NSAttributedString.Key.foregroundColor: stringColor]
    }
    
    func text(_ str:String, _ pt:CGPoint, _ size:CGFloat, _ color:NSColor) {
        stringFont = NSFont.init(name: "Helvetica", size: size)!
        stringColor = color
        stringPrepare()
        
        str.draw(at:pt, withAttributes: stringAtts)
    }
    
    func stringDisplayWidth(_ str:String) -> CGFloat {
        return str.drawSize(font).width
    }
    
    func fillRect(_ rect:CGRect, _ fillColor: CGColor) {
        let path = CGMutablePath()
        path.addRect(rect)
        
        context.beginPath()
        context.setFillColor(fillColor)
        context.addPath(path)
        context.drawPath(using:.fill)
    }
    
    func strokeRect(_ rect:CGRect, _ strokeColor: CGColor) {
        let path = CGMutablePath()
        path.addRect(rect)
        
        context.beginPath()
        context.setStrokeColor(strokeColor)
        context.addPath(path)
        context.drawPath(using:.stroke)
    }
    
    func fillCircle(_ center:CGPoint, _ diameter:CGFloat, _ color:CGColor) {
        context.beginPath()
        context.addEllipse(in: CGRect(x:CGFloat(center.x - diameter/2), y:CGFloat(center.y - diameter/2), width:CGFloat(diameter), height:CGFloat(diameter)))
        context.setFillColor(color)
        context.fillPath()
    }

    func drawBorder(_ rect:CGRect) {
        let p1  = CGPoint(x:rect.minX, y:rect.minY)
        let p2  = CGPoint(x:rect.minX + rect.width, y:rect.minY)
        let p3  = CGPoint(x:rect.minX + rect.width, y:rect.minY + rect.height)
        let p4  = CGPoint(x:rect.minX, y:rect.minY + rect.height)

        func line(_ p1:CGPoint, _ p2:CGPoint, _ strokeColor:CGColor) {
            let path = CGMutablePath()
            path.move( to: p1)
            path.addLine(to: p2)
            
            context.beginPath()
            context.setStrokeColor(strokeColor)
            context.addPath(path)
            context.drawPath(using:.stroke)
        }

        context.setLineWidth(3)
        line(p1,p2,colorGray1)
        line(p1,p4,colorGray1)
        line(p2,p3,colorGray3)
        line(p3,p4,colorGray3)
    }
    
    func line(_ p1:CGPoint, _ p2:CGPoint, _ strokeColor:CGColor) {
        let path = CGMutablePath()
        path.move( to: p1)
        path.addLine(to: p2)

        context.beginPath()
        context.setLineWidth(1.0)
        context.setStrokeColor(strokeColor)
        context.addPath(path)
        context.drawPath(using:.stroke)
    }

    func vLine(_ x:CGFloat, _ y1:CGFloat, _ y2:CGFloat, _ color:CGColor) { line(CGPoint(x:x,y:y1),CGPoint(x:x,y:y2),color) }
    func hLine(_ x1:CGFloat, _ x2:CGFloat, _ y:CGFloat, _ color:CGColor) { line(CGPoint(x:x1,y:y),CGPoint(x:x2,y:y),color) }
    
    func drawLineSet(_ path:CGMutablePath, _ width:CGFloat, _ strokeColor:CGColor) {
        context.beginPath()
        context.setLineWidth(width)
        context.setStrokeColor(strokeColor)
        context.addPath(path)
        context.drawPath(using:.stroke)
    }
    
    func drawFilledPath(_ path:CGMutablePath, _ fillColor: CGColor) {
        context.beginPath()
        context.setFillColor(fillColor)
        context.addPath(path)
        context.drawPath(using:.fill)
    }
}

// -----------------------------------------------

extension String {
    func drawSize(_ font: NSFont) -> CGSize {
        return (self as NSString).size(withAttributes: [NSAttributedString.Key.font: font])
    }
}


