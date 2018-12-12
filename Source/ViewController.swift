import Cocoa
import MetalKit

var vc:ViewController! = nil
var g = Graphics()

class ViewController: NSViewController, NSWindowDelegate, WGDelegate {
    var shadowFlag:Bool = false
    var control = Control()
    var threadGroupCount = MTLSize()
    var threadGroups = MTLSize()
    var cBuffer:MTLBuffer! = nil
    var colorBuffer:MTLBuffer! = nil
    var texture1: MTLTexture!
    var texture2: MTLTexture!
    var pipeline:[MTLComputePipelineState] = []
    let queue = DispatchQueue(label:"Q")
    
    lazy var device: MTLDevice! = MTLCreateSystemDefaultDevice()
    lazy var defaultLibrary: MTLLibrary! = { self.device.makeDefaultLibrary() }()
    lazy var commandQueue: MTLCommandQueue! = { return self.device.makeCommandQueue() }()
    
    @IBOutlet var wg: WidgetGroup!
    @IBOutlet var metalTextureViewL: MetalTextureView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        vc = self
        wg.delegate = self

        cBuffer = device.makeBuffer(bytes: &control, length: MemoryLayout<Control>.stride, options:MTLResourceOptions.storageModeShared)

        let defaultLibrary:MTLLibrary! = device.makeDefaultLibrary()

        let jbSize = MemoryLayout<float3>.stride * 256
        colorBuffer = device.makeBuffer(length:jbSize, options:MTLResourceOptions.storageModeShared)
        colorBuffer.contents().copyMemory(from:colorMap, byteCount:jbSize)

        //------------------------------
        func loadShader(_ name:String) -> MTLComputePipelineState {
            do {
                guard let fn = defaultLibrary.makeFunction(name: name)  else { print("shader not found: " + name); exit(0) }
                return try device.makeComputePipelineState(function: fn)
            }
            catch { print("pipeline failure for : " + name); exit(0) }
        }
        
        let shaderNames = [ "fractalShader","shadowShader" ]
        for i in 0 ..< shaderNames.count { pipeline.append(loadShader(shaderNames[i])) }
        //------------------------------

        let w = pipeline[0].threadExecutionWidth
        let h = pipeline[0].maxTotalThreadsPerThreadgroup / w
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
        
        control.coloringFlag = 1
        control.variation = 0
        
        reset()
    }
    
    //MARK: -
    
    func resizeIfNecessary() {
        let minWinSize:CGSize = CGSize(width:700, height:800)
        var r:CGRect = (view.window?.frame)!
        var needSizing:Bool = false

        if r.size.width  < minWinSize.width  { r.size.width = minWinSize.width; needSizing = true }
        if r.size.height < minWinSize.height { r.size.height = minWinSize.height; needSizing = true }
        
        if needSizing {
            view.window?.setFrame(r, display: true)
        }
    }
    
    func windowDidResize(_ notification: Notification) {
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
    
    var zoomValue:Float = 0
    var panX:Float = 0
    var panY:Float = 0
    
    @objc func timerHandler() {
        var refreshNeeded:Bool = wg.update()
        if zoomValue != 0 || panX != 0 || panY != 0 { refreshNeeded = true }
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
        zoomValue = 0
        panX = 0
        panY = 0
        
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

        wg.addLine()
        wg.addCommand("X",String(format:"Variation %d",control.variation),.variation)

        switch control.variation {
        case 0,1 :
            wg.addSingleFloat("P",&control.power,0.5,5,0.0002, "Power")
            if control.variation == 1 {
                wg.addSingleFloat("Q",&control.foamQ,-1,2,0.001,"foamQ")
                wg.addSingleFloat("W",&control.foamW,-1,2,0.001,"foamW")
            }
        default : break
        }

        wg.addLine()
        wg.addColoredCommand("D",.shadow,"Shadow")
        
        wg.addLine()
        wg.addColor(.coloring,Float(RowHT)*7)
        wg.addCommand("T","Coloring",.coloring)
        wg.addSingleFloat("2",&control.stripeDensity,-10,10,0.03, "Stripe")
        wg.addSingleFloat("3",&control.escapeRadius,0.01,15,0.01, "Escape")
        wg.addSingleFloat("4",&control.multiplier,-2,2,0.01, "Mult")
        wg.addSingleFloat("5",&control.R,0,1,0.008, "Color R")
        wg.addSingleFloat("6",&control.G,0,1,0.008, "Color G")
        wg.addSingleFloat("7",&control.B,0,1,0.008, "Color B")
        
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
        wg.addCommand("V","Save/Load",.saveLoad)
        wg.addCommand("L","Load Next",.loadNext)
        wg.addCommand("H","Help",.help)

        wg.refresh()
    }
    
    //MARK: -
    
    func wgCommand(_ cmd: WgIdent) {
        func presentPopover(_ name:String) {
            let mvc = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: nil)
            let vc = mvc.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier(name)) as! NSViewController
            self.present(vc, asPopoverRelativeTo: wg.bounds, of: wg, preferredEdge: .maxX, behavior: .transient)
        }
        
        switch(cmd) {
        case .saveLoad : presentPopover("SaveLoadVC")
        case .help : presentPopover("HelpVC")
            
        case .reset : reset()
        case .coloring :
            control.coloringFlag = control.coloringFlag == 0 ? 1 : 0
            updateImage()
            
        case .variation :
            control.variation += 1
            if control.variation >= NUM_VARIATION { control.variation = 0 }
            initializeWidgetGroup()
            wgCommand(.reset)

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
        case .shadow   : highlight = shadowFlag
        case .coloring : highlight = control.coloringFlag > 0
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
    
    func layoutViews() {
        let xs = view.bounds.width
        let ys = view.bounds.height
        let xBase:CGFloat = wg.isHidden ? 0 : 140
        
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
        
        texture1 = device.makeTexture(descriptor: textureDescriptor)!
        texture2 = device.makeTexture(descriptor: textureDescriptor)!

        metalTextureViewL.initialize(texture1)
        
        let xs = xsz/threadGroupCount.width + 1
        let ys = ysz/threadGroupCount.height + 1
        threadGroups = MTLSize(width:xs, height:ys, depth: 1)
    }
    
    //MARK: -
    
    func calcFractal() {
        // pan ----------------
        let mx = (control.xmax - control.xmin) * panX / 100
        let my = -(control.ymax - control.ymin) * panY / 100
        control.xmin -= mx
        control.xmax -= mx
        control.ymin -= my
        control.ymax -= my
        
        // zoom ---------------
        let amount:Float = (1.0 - zoomValue)
        let xsize = (control.xmax - control.xmin) * amount
        let ysize = (control.ymax - control.ymin) * amount
        let xc = (control.xmin + control.xmax) / 2
        let yc = (control.ymin + control.ymax) / 2
        control.xmin = xc - xsize/2
        control.xmax = xc + xsize/2
        control.ymin = yc - ysize/2
        control.ymax = yc + ysize/2
        
        panX = 0  // reset change amounts
        panY = 0
        zoomValue = 0

        control.dx = (control.xmax - control.xmin) / Float(control.xSize)
        control.dy = (control.ymax - control.ymin) / Float(control.ySize)
        cBuffer.contents().copyMemory(from: &control, byteCount:MemoryLayout<Control>.stride)
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
        
        commandEncoder.setComputePipelineState(pipeline[0])
        commandEncoder.setTexture(texture1, index: 0)
        commandEncoder.setBuffer(cBuffer, offset: 0, index: 0)
        commandEncoder.setBuffer(colorBuffer, offset: 0, index: 1)
        
        commandEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)
        commandEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        if shadowFlag {
            let commandBuffer = commandQueue.makeCommandBuffer()!
            let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
            
            commandEncoder.setComputePipelineState(pipeline[1])
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
    }
    
    //MARK: -
    
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
    
    override func scrollWheel(with event: NSEvent) {
        zoomValue = Float(event.deltaY/20)
    }
    
}

// ===============================================

class BaseNSView: NSView {
    override var acceptsFirstResponder: Bool { return true }
}
