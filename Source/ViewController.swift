import Cocoa
import MetalKit

var vc:ViewController! = nil
var g = Graphics()
var win3D:NSWindowController! = nil
var cBuffer:MTLBuffer! = nil
var colorBuffer:MTLBuffer! = nil

class ViewController: NSViewController, NSWindowDelegate, WGDelegate {
    var shadowFlag:Bool = false
    var control = Control()
    var threadGroupCount = MTLSize()
    var threadGroups = MTLSize()
    var texture1: MTLTexture!
    var texture2: MTLTexture!
    var pipeline:[MTLComputePipelineState] = []
    let queue = DispatchQueue(label:"Q")
    var offset3D = SIMD3<Float>()
    var autoChange:Bool = false
    
    lazy var device2D: MTLDevice! = MTLCreateSystemDefaultDevice()
    lazy var defaultLibrary: MTLLibrary! = { self.device2D.makeDefaultLibrary() }()
    lazy var commandQueue: MTLCommandQueue! = { return self.device2D.makeCommandQueue() }()
    
    @IBOutlet var wg: WidgetGroup!
    @IBOutlet var metalTextureViewL: MetalTextureView!
    
    let PIPELINE_FRACTAL = 0
    let PIPELINE_SHADOW  = 1
    let shaderNames = [ "fractalShader","shadowShader" ]

    override func viewDidLoad() {
        super.viewDidLoad()
        vc = self
        wg.delegate = self
        
        cBuffer = device2D.makeBuffer(bytes: &control, length: MemoryLayout<Control>.stride, options:MTLResourceOptions.storageModeShared)
        
        let defaultLibrary:MTLLibrary! = device2D.makeDefaultLibrary()
        
        let jbSize = MemoryLayout<SIMD3<Float>>.stride * 256
        colorBuffer = device2D.makeBuffer(length:jbSize, options:MTLResourceOptions.storageModeShared)
        colorBuffer.contents().copyMemory(from:colorMap, byteCount:jbSize)
        
        //------------------------------
        func loadShader(_ name:String) -> MTLComputePipelineState {
            do {
                guard let fn = defaultLibrary.makeFunction(name: name)  else { print("shader not found: " + name); exit(0) }
                return try device2D.makeComputePipelineState(function: fn)
            }
            catch { print("pipeline failure for : " + name); exit(0) }
        }
        
        for i in 0 ..< shaderNames.count { pipeline.append(loadShader(shaderNames[i])) }
        //------------------------------
        
        let w = pipeline[PIPELINE_FRACTAL].threadExecutionWidth
        let h = pipeline[PIPELINE_FRACTAL].maxTotalThreadsPerThreadgroup / w
        threadGroupCount = MTLSizeMake(w, h, 1)
        
        setControlPointer(&control)
        initializeWidgetGroup()
        layoutViews()
        
        Timer.scheduledTimer(withTimeInterval:0.05, repeats:true) { timer in self.timerHandler() }
    }
    
    override func viewDidAppear() {
        view.window?.delegate = self    // so we received window size changed notifications
        resizeIfNecessary()
        dvrCount = 1 // resize metalview without delay
        
        control.win3DFlag = 0
        control.coloringFlag = 1
        control.variation = 0
    }
    
    func windowWillClose(_ aNotification: Notification) {
        if let w = win3D { w.close() }
    }
    
    func win3DClosed() {
        win3D = nil
        control.win3DFlag = 0
        wg.refresh()
        updateImage() // to erase bounding box
    }
    
    //MARK: -
    
    func resizeIfNecessary() {
        let minWinSize:CGSize = CGSize(width:700, height:835)
        var r:CGRect = (view.window?.frame)!
        var needSizing:Bool = false
        
        if r.size.width  < minWinSize.width  { r.size.width = minWinSize.width; needSizing = true }
        if r.size.height < minWinSize.height { r.size.height = minWinSize.height; needSizing = true }
        
        if needSizing {
            view.window?.setFrame(r, display: true)
        }
    }
    
    func windowDidResize(_ notification: Notification) {
        reset()
        resizeIfNecessary()
        resetDelayedViewResizing()
    }
    
    //MARK: -
    
    var dvrCount:Int = 0
    
    // don't realloc metalTextures until they have finished resizing the window
    func resetDelayedViewResizing() {
        dvrCount = 10 // 20 = 1 second delay
    }
    
    //MARK: -
    
    var isMorph:Bool = true
    
    var zoomValue:Float = 0
    var panX:Float = 0
    var panY:Float = 0
    var morphAngle:Float = 0
    
    func updateMorphingValues() -> Bool {
        var wasMorphed:Bool = false
        
        if isMorph {
            let s = sin(morphAngle)
            morphAngle += 0.001
            
            for index in 0 ..< wg.data.count {
                if wg.alterValueViaMorph(index,s) { wasMorphed = true }
            }
        }
        
        return wasMorphed
    }
    
    @objc func timerHandler() {
        var refreshNeeded:Bool = wg.update()
        if autoChange { refreshNeeded = refreshNeeded || updateMorphingValues() }
        if zoomValue != 0 || panX != 0 || panY != 0 || offset3D.x != 0 || offset3D.y != 0 || offset3D.z != 0 { refreshNeeded = true }
        
        if refreshNeeded { updateImage() }
        
        if dvrCount > 0 {
            dvrCount -= 1
            if dvrCount <= 0 {
                layoutViews()
            }
        }
    }
    
    //MARK: -
    
    func reset() {
        if let w = win3D { w.close() }

        offset3D = SIMD3<Float>()
        zoomValue = 0
        panX = 0
        panY = 0
        
        control.retry = 0
        control.power = 2
        control.xmin = -2
        control.xmax = 1
        control.ymin = -1.5
        control.ymax = 1.5
        control.skip = 20
        control.stripeDensity = -1.343
        control.escapeRadius = 4
        control.multiplier = -0.381
        control.R = 0
        control.G = 0.4
        control.B = 0.7
        control.maxIter = 200
        control.contrast = 4
        
        control.foamQ = -0.5
        control.foamW = 0.2
        
        control.height = 0.1
        
        updateImage()
        wg.hotKey("M")
    }
    
    //MARK: -
    
    func initializeWidgetGroup() {
        let coloringHeight:Float = Float(RowHT - 2)
        wg.reset()
        wg.addCommand("R","Reset",.reset)
        wg.addSingleFloat("Z",&zoomValue,-1,1,0.01, "Zoom")
        wg.addDualFloat("M",&panX,&panY,-10,10,1, "Move")
        
        wg.addLine()
        wg.addSingleFloat("I",&control.maxIter,40,200,3,"maxIter")
        wg.addSingleFloat("C",&control.contrast,0.1,5,0.03, "Contrast")
        wg.addSingleFloat("S",&control.skip,1,100,0.2,"Skip")
        wg.addCommand("K",String(format:"Retry %d",control.retry),.retry)

        wg.addLine()
        wg.addCommand("X",String(format:"Variation %d",control.variation),.variation)
        
        switch control.variation {
        case 0,1,3,4,5,6,7 :
            wg.addSingleFloat("P",&control.power,0.5,25,0.0002, "Power",true)
            if control.variation == 1 {
                wg.addSingleFloat("Q",&control.foamQ,-1,2,0.001,"foamQ",true)
                wg.addSingleFloat("W",&control.foamW,-1,2,0.001,"foamW",true)
            }
        default : break
        }
        
        wg.addLine()
        wg.addColor(.win3D,Float(RowHT)*2)
        wg.addCommand("L","3D Window",.win3D)
        wg.addTriplet("J",&offset3D,-1,1,0.1, "3D ROI")
        
        wg.addLine()
        wg.addColoredCommand("D",.shadow,"Shadow")
        
        wg.addLine()
        wg.addColor(.coloring,Float(RowHT)*7)
        wg.addCommand("T","Coloring",.coloring)
        wg.addSingleFloat("2",&control.stripeDensity,-10,10,0.03, "Stripe",true)
        wg.addSingleFloat("3",&control.escapeRadius,0.01,15,0.01, "Escape",true)
        wg.addSingleFloat("4",&control.multiplier,-2,2,0.01, "Mult",true)
        wg.addSingleFloat("5",&control.R,0,1,0.008, "Color R",true)
        wg.addSingleFloat("6",&control.G,0,1,0.008, "Color G",true)
        wg.addSingleFloat("7",&control.B,0,1,0.008, "Color B",true)
        
        // ------------------------------------
        func pointTrapGroup(_ index:Int, _ cmd:WgIdent) {
            wg.addLine()
            wg.addColor(cmd,Float(RowHT)*2+3)
            wg.addCommand("",String(format:"PTrap #%d",index+1),cmd)
            wg.addDualFloat("",PTrapX(Int32(index)),PTrapY(Int32(index)),-10,10,0.1, "Point")
        }
        
        func lineTrapGroup(_ index:Int, _ cmd:WgIdent) {
            wg.addLine()
            wg.addColor(cmd,Float(RowHT)*3+3)
            wg.addCommand("",String(format:"LTrap #%d",index+1),cmd)
            wg.addDualFloat("",LTrapX(Int32(index)),LTrapY(Int32(index)),-10,10,0.1, "Point")
            wg.addSingleFloat("",LTrapS(Int32(index)),-10,10,0.05,"Slope")
        }
        
        pointTrapGroup(0,.pt0)
        pointTrapGroup(1,.pt1)
        pointTrapGroup(2,.pt2)
        
        lineTrapGroup(0,.lt0)
        lineTrapGroup(1,.lt1)
        lineTrapGroup(2,.lt2)
        // ------------------------------------
        
        wg.addLine()
        wg.addColor(.autoChange,Float(RowHT))
        wg.addCommand("A","AutoChange",.autoChange)
        wg.addCommand("V","Save/Load",.saveLoad)
        wg.addCommand("L","Load Next",.loadNext)
        wg.addCommand("H","Help",.help)
        
        wg.refresh()
    }
    
    func toggle3DView() {
        control.win3DFlag = control.win3DFlag > 0 ? 0 : 1
        
        if control.win3DFlag > 0 {
            if win3D == nil {
                let mainStoryboard = NSStoryboard.init(name: NSStoryboard.Name("Main"), bundle: nil)
                win3D = mainStoryboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("Win3D")) as? NSWindowController
            }
            
            control.xmin3D = -1.60189855
            control.xmax3D = -0.976436495
            control.ymin3D = -0.20827961
            control.ymax3D = 0.235990882
            win3D.showWindow(self)
        }
        else {
            win3D.close()
        }
        
        updateImage()
    }
    
    //MARK: -
    
    func wgCommand(_ cmd: WgIdent) {
        func presentPopover(_ name:String) {
            let mvc = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: nil)
            let vc = mvc.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier(name)) as! NSViewController
            self.present(vc, asPopoverRelativeTo: wg.bounds, of: wg, preferredEdge: .maxX, behavior: .transient)
        }
        
        switch(cmd) {
        case .win3D :
            toggle3DView()
        case .saveLoad :
            presentPopover("SaveLoadVC")
        case .help :
            helpIndex = 0
            presentPopover("HelpVC")
            
        case .reset : reset()
        case .coloring :
            control.coloringFlag = control.coloringFlag == 0 ? 1 : 0
            updateImage()
            
        case .variation :
            if control.win3DFlag > 0 {
                win3D.close()
                win3DClosed()
            }
            
            control.retry = 0
            control.variation += 1
            if control.variation >= NUM_VARIATION { control.variation = 0 }
            initializeWidgetGroup()
            wgCommand(.reset)
            
        case .retry :
            control.retry += 1
            if control.retry > 5 { control.retry = 0 }
            initializeWidgetGroup()
            updateImage()

        case .shadow :
            shadowFlag = !shadowFlag
            metalTextureViewL.initialize(shadowFlag ? texture2 : texture1)
            updateImage()
            
        case .loadNext :
            let ss = SaveLoadViewController()
            ss.loadNext()
            updateImage()
            
        case .pt0 :
            togglePointTrap(0)
            updateImage()
        case .pt1 :
            togglePointTrap(1)
            updateImage()
        case .pt2 :
            togglePointTrap(2)
            updateImage()
        case .lt0 :
            toggleLineTrap(0)
            updateImage()
        case .lt1 :
            toggleLineTrap(1)
            updateImage()
        case .lt2 :
            toggleLineTrap(2)
            updateImage()
            
        case .autoChange :
            autoChange = !autoChange
            initializeWidgetGroup()
        default : break
        }
        
        wg.refresh()
    }
    
    func wgToggle(_ ident:WgIdent) {
        switch(ident) {
        default : break
        }
        
        wg.refresh()
    }
    
    func wgGetString(_ ident:WgIdent) -> String {
        switch ident {
        default : return ""
        }
    }
    
    func wgGetColor(_ ident:WgIdent) -> NSColor {
        var highlight:Bool = false
        switch(ident) {
        case .win3D    : highlight = control.win3DFlag > 0
        case .shadow   : highlight = shadowFlag
        case .coloring : highlight = control.coloringFlag > 0
        case .autoChange : highlight = autoChange
        case .pt0 : highlight = getPTrapActive(0) > 0
        case .pt1 : highlight = getPTrapActive(1) > 0
        case .pt2 : highlight = getPTrapActive(2) > 0
        case .lt0 : highlight = getLTrapActive(0) > 0
        case .lt1 : highlight = getLTrapActive(1) > 0
        case .lt2 : highlight = getLTrapActive(2) > 0
        default : break
        }
        
        return highlight ? wgHighlightColor : wgBackgroundColor
    }
    
    func wgOptionSelected(_ ident: WgIdent, _ index: Int) {}
    func wgGetOptionString(_ ident: WgIdent) -> String { return "" }
    
    //MARK: -
    
    let WGWidth:CGFloat = 140
    
    func layoutViews() {
        let xs = view.bounds.width
        let ys = view.bounds.height
        let xBase:CGFloat = wg.isHidden ? 0 : WGWidth
        
        if !wg.isHidden { wg.frame = CGRect(x:1, y:1, width:xBase-1, height:ys-2) }
        
        metalTextureViewL.frame = CGRect(x:xBase+1, y:1, width:xs-xBase-2, height:ys-2)
        
        setImageViewResolution()
        updateImage()
    }
    
    func controlJustLoaded() {
        initializeWidgetGroup()
        wg.refresh()
        setImageViewResolution()
        updateImage()
    }
    
    func setImageViewResolution() {
        control.xSize = Int32(metalTextureViewL.frame.width)
        control.ySize = Int32(metalTextureViewL.frame.height)
        let xsz = Int(control.xSize)
        let ysz = Int(control.ySize)
        
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: xsz,
            height: ysz,
            mipmapped: false)
        
        texture1 = device2D.makeTexture(descriptor: textureDescriptor)!
        texture2 = device2D.makeTexture(descriptor: textureDescriptor)!
        
        metalTextureViewL.initialize(texture1)
        
        let xs = xsz/threadGroupCount.width + 1
        let ys = ysz/threadGroupCount.height + 1
        threadGroups = MTLSize(width:xs, height:ys, depth: 1)
    }
    
    //MARK: -
    
    func updateRegionsOfInterest() {
        // pan ----------------
        if panX != 0 || panY != 0 {
            let mx = (control.xmax - control.xmin) * panX / 100
            let my = -(control.ymax - control.ymin) * panY / 100
            control.xmin -= mx
            control.xmax -= mx
            control.ymin -= my
            control.ymax -= my
            panX = 0
            panY = 0
        }
        
        // zoom ---------------
        if zoomValue != 0 {
            let amount:Float = (1.0 - zoomValue)
            let xsize = (control.xmax - control.xmin) * amount
            let ysize = (control.ymax - control.ymin) * amount
            let xc = (control.xmin + control.xmax) / 2
            let yc = (control.ymin + control.ymax) / 2
            control.xmin = xc - xsize/2
            control.xmax = xc + xsize/2
            control.ymin = yc - ysize/2
            control.ymax = yc + ysize/2
            zoomValue = 0
        }
        
        // 3D pan, zoom --------------
        if offset3D != SIMD3<Float>() {
            let dx:Float = offset3D.x * control.dx * 5
            let dy:Float = -offset3D.y * control.dy * 5
            control.xmin3D += dx; control.xmax3D += dx
            control.ymin3D += dy; control.ymax3D += dy
            
            if offset3D.z != 0 {
                let amount:Float = (1.0 - offset3D.z)
                var xsize = (control.xmax3D - control.xmin3D) * amount
                var ysize = (control.ymax3D - control.ymin3D) * amount
                let minSz:Float = 0.001
                if xsize < minSz { xsize = minSz }
                if ysize < minSz { ysize = minSz }
                let xc = (control.xmin3D + control.xmax3D) / 2
                let yc = (control.ymin3D + control.ymax3D) / 2
                control.xmin3D = xc - xsize/2
                control.xmax3D = xc + xsize/2
                control.ymin3D = yc - ysize/2
                control.ymax3D = yc + ysize/2
            }
            offset3D = SIMD3<Float>()
        }
        
        control.dx = (control.xmax - control.xmin) / Float(control.xSize)
        control.dy = (control.ymax - control.ymin) / Float(control.ySize)
        control.dx3D = (control.xmax3D - control.xmin3D) / Float(SIZE3D)
        control.dy3D = (control.ymax3D - control.ymin3D) / Float(SIZE3D)
    }
    
    //MARK: -
    
    func calcFractal() {
        
//        print("pow: ", control.power.debugDescription, "  it: ", control.maxIter.debugDescription)
        
        updateRegionsOfInterest()
        
        control.is3DWindow = 0
        
        cBuffer.contents().copyMemory(from: &control, byteCount:MemoryLayout<Control>.stride)
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
        
        commandEncoder.setComputePipelineState(pipeline[PIPELINE_FRACTAL])
        commandEncoder.setTexture(texture1, index: 0)
        
        // skip unused buffer 0
        // Swift 5   app is screwed up if you skip loading a buffer
        // so, load cBuffer, just to make it happy
        commandEncoder.setBuffer(cBuffer, offset: 0, index: 0)
        
        commandEncoder.setBuffer(cBuffer, offset: 0, index: 1)
        commandEncoder.setBuffer(colorBuffer, offset: 0, index: 2)
        
        commandEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)
        commandEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        if shadowFlag {
            let commandBuffer = commandQueue.makeCommandBuffer()!
            let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
            
            commandEncoder.setComputePipelineState(pipeline[PIPELINE_SHADOW])
            commandEncoder.setTexture(texture1, index: 0)
            commandEncoder.setTexture(texture2, index: 1)
            commandEncoder.setBuffer(cBuffer, offset: 0, index: 0)
            commandEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)
            commandEncoder.endEncoding()
            
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
    }
    
    //MARK: -
    
    func updateImage() {
        calcFractal()
        metalTextureViewL.display(metalTextureViewL.layer!)
        
        if win3D != nil {
            vc3D.calcFractal()
        }
    }
    
    //MARK: -
    
    func isOptionKeyDown() -> Bool { return optionKeyDown }
    func isShiftKeyDown() -> Bool { return shiftKeyDown }
    func isLetterAKeyDown() -> Bool { return letterAKeyDown }

    var shiftKeyDown:Bool = false
    var optionKeyDown:Bool = false
    var letterAKeyDown:Bool = false
    
    override func keyDown(with event: NSEvent) {
        super.keyDown(with: event)
        
        updateModifierKeyFlags(event)
        
        switch event.keyCode {
        case 123:   // Left arrow
            wg.hopValue(-1,0)
            return
        case 124:   // Right arrow
            wg.hopValue(+1,0)
            return
        case 125:   // Down arrow
            wg.hopValue(0,-1)
            return
        case 126:   // Up arrow
            wg.hopValue(0,+1)
            return
        case 43 :   // '<'
            wg.moveFocus(-1)
            return
        case 47 :   // '>'
            wg.moveFocus(1)
            return
        case 53 :   // Esc
            NSApplication.shared.terminate(self)
        case 0 :    // A
            letterAKeyDown = true
        case 18 :   // 1
            wg.isHidden = !wg.isHidden
            layoutViews()
        case 36 :   // <return>
            wg.togglealterValueViaMorph()
            return
        default:
            break
        }
        
        let keyCode = event.charactersIgnoringModifiers!.uppercased()
        //print("KeyDown ",keyCode,event.keyCode)
        
        wg.hotKey(keyCode)
    }
    
    override func keyUp(with event: NSEvent) {
        super.keyUp(with: event)
        
        wg.stopChanges()
        
        switch event.keyCode {
        case 0 :    // A
            letterAKeyDown = false
        default:
            break
        }        
    }
    
    //MARK: -
    
    func flippedYCoord(_ pt:NSPoint) -> NSPoint {
        var npt = pt
        npt.y = view.bounds.size.height - pt.y
        return npt
    }
    
    func updateModifierKeyFlags(_ ev:NSEvent) {
        let rv = ev.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
        shiftKeyDown   = rv & (1 << 17) != 0
        optionKeyDown  = rv & (1 << 19) != 0
    }
    
    var pt = NSPoint()
    
    override func mouseDown(with event: NSEvent) {
        pt = flippedYCoord(event.locationInWindow)
    }
    
    override func mouseDragged(with event: NSEvent) {
        updateModifierKeyFlags(event)
        
        var npt = flippedYCoord(event.locationInWindow)
        npt.x -= pt.x
        npt.y -= pt.y
        wg.focusMovement(npt,1)
    }
    
    override func mouseUp(with event: NSEvent) {
        pt.x = 0
        pt.y = 0
        wg.focusMovement(pt,0)
    }
    
    //MARK: -
    
    enum Win3DState { case initial,move }
    
    func win3DMap(_ pt:NSPoint, _ state:Win3DState) {
        var pt = pt
        if !wg.isHidden { pt.x -= WGWidth }
        
        let c:SIMD2<Float> = SIMD2<Float>(Float(control.xmin + control.dx * Float(pt.x)), Float(control.ymin + control.dy * Float(pt.y)))
        
        switch(state) {
        case .initial :
            control.xmin3D = c.x; control.xmax3D = c.x
            control.ymin3D = c.y; control.ymax3D = c.y
        case .move :
            if c.x < control.xmin3D { control.xmin3D = c.x }
            if c.x > control.xmax3D { control.xmax3D = c.x }
            if c.y < control.ymin3D { control.ymin3D = c.y }
            if c.y > control.ymax3D { control.ymax3D = c.y }
            updateImage()
            vc3D.calcFractal()
        }
    }
    
    override func rightMouseDown(with event: NSEvent) {
        if control.win3DFlag > 0 {
            win3DMap(flippedYCoord(event.locationInWindow),.initial)
        }
    }
    
    override func rightMouseDragged(with event: NSEvent) {
        if control.win3DFlag > 0 {
            win3DMap(flippedYCoord(event.locationInWindow),.move)
        }
    }
    
    //MARK: -
    
    override func scrollWheel(with event: NSEvent) {
        zoomValue = Float(event.deltaY/20)
    }
}

// ===============================================

class BaseNSView: NSView {
    override var acceptsFirstResponder: Bool { return true }
}

import Foundation

// wrapper function for shell commands
// must provide full path to executable
func shell(_ launchPath: String, _ arguments: [String] = []) -> (String?, Int32) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: launchPath)
    task.arguments = arguments
    
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe
    
    do {
        try task.run()
    } catch {
        // handle errors
        print("Error: \(error.localizedDescription)")
    }
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)
    
    task.waitUntilExit()
    return (output, task.terminationStatus)
}

func cTest() {
// valid directory listing test
let (goodOutput, goodStatus) = shell("/bin/ls", ["-la"])
if let out = goodOutput { print("\(out)") }
print("Returned \(goodStatus)\n")
}


