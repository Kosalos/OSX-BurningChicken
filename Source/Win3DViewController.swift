import Cocoa
import MetalKit

var vc3D:Win3DViewController! = nil
let view3D = View3D()
var device3D:MTLDevice! = nil
var camera:SIMD3<Float> = SIMD3<Float>(0,0.2,-200)

class Win3DViewController: NSViewController, NSWindowDelegate, WGDelegate {
    var isStereo:Bool = false
    var rendererL: Renderer!
    var rendererR: Renderer!
    var threadGroupCount = MTLSize()
    var threadGroups = MTLSize()
    var pipeline:[MTLComputePipelineState] = []
    let queue = DispatchQueue(label:"Q")
    
    lazy var defaultLibrary: MTLLibrary! = { device3D.makeDefaultLibrary() }()
    lazy var commandQueue: MTLCommandQueue! = { return device3D.makeCommandQueue() }()
    
    @IBOutlet var wg: WidgetGroup!
    @IBOutlet var d3ViewL: MTKView!
    @IBOutlet var d3ViewR: MTKView!
    
    let PIPELINE_FRACTAL = 0
    let PIPELINE_NORMAL  = 1
    let PIPELINE_SMOOTH  = 2
    let shaderNames = [ "fractalShader","normalShader","smoothingShader" ]

    override func viewDidLoad() {
        super.viewDidLoad()
        vc3D = self
        wg.delegate = self
        
        device3D = MTLCreateSystemDefaultDevice()
        d3ViewL.device = device3D
        d3ViewR.device = device3D
        view3D.initialize()

        guard let newRenderer = Renderer(metalKitView: d3ViewL, 0) else { fatalError("Renderer cannot be initialized") }
        rendererL = newRenderer
        rendererL.mtkView(d3ViewL, drawableSizeWillChange: d3ViewL.drawableSize)
        d3ViewL.delegate = rendererL
        
        guard let newRenderer2 = Renderer(metalKitView: d3ViewR, 1) else { fatalError("Renderer cannot be initialized") }
        rendererR = newRenderer2
        rendererR.mtkView(d3ViewR, drawableSizeWillChange: d3ViewR.drawableSize)
        d3ViewR.delegate = rendererR
        
        //------------------------------
        let defaultLibrary:MTLLibrary! = device3D.makeDefaultLibrary()
        
        func loadShader(_ name:String) -> MTLComputePipelineState {
            do {
                guard let fn = defaultLibrary.makeFunction(name: name)  else { print("shader not found: " + name); exit(0) }
                return try device3D.makeComputePipelineState(function: fn)
            }
            catch { print("pipeline failure for : " + name); exit(0) }
        }
        
        for i in 0 ..< shaderNames.count { pipeline.append(loadShader(shaderNames[i])) }
        //------------------------------
        
        let w = pipeline[0].threadExecutionWidth
        let h = pipeline[0].maxTotalThreadsPerThreadgroup / w
        threadGroupCount = MTLSizeMake(w, h, 1)
     
        let sz:Int = Int(SIZE3D)
        let xs = sz / threadGroupCount.width + 1
        let ys = sz / threadGroupCount.height + 1
        threadGroups = MTLSize(width:xs, height:ys, depth: 1)
        
        initializeWidgetGroup()
        layoutViews()

        light.base = SIMD3<Float>(20,1,0)
        light.radius = 50
        light.deltaAngle = 0.002
        light.power = 1.3
        light.ambient = 0.1
        light.height = 1
        vc.control.smooth = 1

        Timer.scheduledTimer(withTimeInterval:0.05, repeats:true) { timer in self.timerHandler() }
    }
    
    override func viewDidAppear() {
        view.window?.delegate = self    // so we received window size changed notifications
        resizeIfNecessary()
        dvrCount = 1 // resize metalview without delay
        reset()
    }
    
    func windowWillClose(_ aNotification: Notification) {
        vc.win3DClosed()
    }
    
    //MARK: -
    
    func resizeIfNecessary() {
        let minWinSize:CGSize = CGSize(width:700, height:500)
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
    
    var viewCenter = CGPoint()
    var paceRotate = CGPoint()

    func rotate(_ pt:CGPoint) {
        arcBall.mouseDown(viewCenter)
        arcBall.mouseMove(CGPoint(x:viewCenter.x + pt.x, y:viewCenter.y - pt.y))
    }
    
    @objc func timerHandler() {
        rotate(paceRotate)
        if wg.update() { calcFractal() }
        
        if dvrCount > 0 {
            dvrCount -= 1
            if dvrCount <= 0 {
                layoutViews()
                reset()
            }
        }
    }
    
    //MARK: -
    
    func reset() {
        camera = SIMD3<Float>(3.125000e-02, 3.514453e+01, -1.700000e+02)
        arcBall.endPosition = simd_float3x3([-0.98003304, -0.114680395, 0.08034625], [-0.068442315, 0.8726114, 0.46063754], [-0.1268652, 0.44375, -0.8655098])
        arcBall.transformMatrix = simd_float4x4([-0.98003304, -0.114680395, 0.08034625, 0.0], [-0.068442315, 0.8726114, 0.46063754, 0.0], [-0.1268652, 0.44375, -0.8655098, 0.0], [0.0, 0.0, 0.0, 1.0])
    }
    
    //MARK: -
    
    func initializeWidgetGroup() {
        wg.reset()
        wg.addSingleFloat("2",&vc.control.height,-1,1,0.01, "Height")
        wg.addTriplet("M",&camera,-300,300,5, "Move")
        wg.addLine()
        wg.addLegend("Light Controls")
        wg.addSingleFloat("3",&light.power,0.1,2,0.1, "Spread")
        wg.addSingleFloat("4",&light.ambient,0,1,0.01, "Ambient")
        wg.addSingleFloat("5",&light.deltaAngle,0.001,0.05,0.001, "Speed")
        wg.addSingleFloat("6",&light.radius,5,150,4, "Radius")
        wg.addSingleFloat("7",&light.height,-100,100,5, "Height")
        wg.addLine()
        wg.addSingleFloat("8",&vc.control.smooth,0,1,0.02, "Smooth")
        wg.addLine()
        wg.addColor(.stereo,Float(RowHT))
        wg.addCommand("O","Stereo",.stereo)
        wg.addLine()
        wg.addCommand("R","Reset",.reset)
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
        case .stereo :
            isStereo = !isStereo
            layoutViews()
        case .help :
            helpIndex = 1
            presentPopover("HelpVC")
        case .reset : reset()
        default : break
        }
        
        wg.refresh()
    }
    
    func wgToggle(_ ident:WgIdent) {}
    func wgGetString(_ ident:WgIdent) -> String { return "" }
    func wgGetColor(_ ident:WgIdent) -> NSColor { return NSColor.black }
    func wgOptionSelected(_ ident: WgIdent, _ index: Int) {}
    func wgGetOptionString(_ ident: WgIdent) -> String { return "" }
    
    //MARK: -
    
    func layoutViews() {
        let xs = view.bounds.width
        let ys = view.bounds.height
        let xBase:CGFloat = wg.isHidden ? 0 : 130
        
        if !wg.isHidden { wg.frame = CGRect(x:1, y:1, width:xBase-1, height:ys-2) }
        
        d3ViewL.frame = CGRect(x:xBase+1, y:1, width:xs-xBase-2, height:ys-2)
        
        if isStereo {
            d3ViewR.isHidden = false
            let xs2:CGFloat = (xs - xBase)/2
            d3ViewL.frame = CGRect(x:xBase+1, y:1, width:xs2, height:ys-2)
            d3ViewR.frame = CGRect(x:xBase+xs2+1, y:1, width:xs2-2, height:ys-2)
        }
        else {
            d3ViewR.isHidden = true
            d3ViewL.frame = CGRect(x:xBase+1, y:1, width:xs-xBase-2, height:ys-2)
        }
        
        viewCenter.x = d3ViewL.frame.width/2
        viewCenter.y = d3ViewL.frame.height/2
        arcBall.initialize(Float(d3ViewL.frame.width),Float(d3ViewL.frame.height))
        
        reset()
    }
    
    //MARK: -
    
    var isBusy:Bool = false
    
    func calcFractal() {

        if isBusy { return }
        isBusy = true
        
        vc.control.is3DWindow = 1
        cBuffer.contents().copyMemory(from: &vc.control, byteCount:MemoryLayout<Control>.stride)
        
        // 1. determine grid point heights according to fractal settings and region of interest
        // -----------------------------------------------------------------------------------------
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
        commandEncoder.setComputePipelineState(pipeline[PIPELINE_FRACTAL])
        
        // texture buffer unused
        commandEncoder.setBuffer(vBuffer,       offset: 0, index: 0)
        commandEncoder.setBuffer(cBuffer,       offset: 0, index: 1)
        commandEncoder.setBuffer(colorBuffer,   offset: 0, index: 2)
        commandEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)
        commandEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // 2. smooth heights by averaging with neighbors.  vBuffer -> vBuffer2
        // -----------------------------------------------------------------------------------------
        do {
            let commandBuffer = commandQueue.makeCommandBuffer()!
            let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
            commandEncoder.setComputePipelineState(pipeline[PIPELINE_SMOOTH])
            
            commandEncoder.setBuffer(vBuffer,  offset: 0, index: 0)
            commandEncoder.setBuffer(vBuffer2, offset: 0, index: 1)
            commandEncoder.setBuffer(cBuffer,  offset: 0, index: 2)
            commandEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)
            commandEncoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }

        // 3. smooth heights second time.  vBuffer2 -> vBuffer
        // -----------------------------------------------------------------------------------------
        do {
            let commandBuffer = commandQueue.makeCommandBuffer()!
            let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
            commandEncoder.setComputePipelineState(pipeline[PIPELINE_SMOOTH])
            
            commandEncoder.setBuffer(vBuffer2, offset: 0, index: 0)
            commandEncoder.setBuffer(vBuffer,  offset: 0, index: 1)
            commandEncoder.setBuffer(cBuffer,  offset: 0, index: 2)
            commandEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)
            commandEncoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }

        // 4. update grid point normals
        // -----------------------------------------------------------------------------------------
        do {
            let commandBuffer = commandQueue.makeCommandBuffer()!
            let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
            commandEncoder.setComputePipelineState(pipeline[PIPELINE_NORMAL])

            commandEncoder.setBuffer(vBuffer, offset: 0, index: 0)
            commandEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)
            commandEncoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
        
        isBusy = false
    }
    
    //MARK: -
 
    func isOptionKeyDown() -> Bool { return optionKeyDown }
    func isShiftKeyDown() -> Bool { return shiftKeyDown }
    func isLetterAKeyDown() -> Bool { return letterAKeyDown }

    var shiftKeyDown:Bool = false
    var optionKeyDown:Bool = false
    var letterAKeyDown:Bool = false
    
    override func keyDown(with event: NSEvent) {
       // super.keyDown(with: event)
        
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
        
        switch(keyCode) {
        case "[" : tiltAngle -= 0.01
        case "]" : tiltAngle += 0.01
        default  : break
        }
        
        wg.hotKey(keyCode)
    }
    
    override func keyUp(with event: NSEvent) {
        //super.keyUp(with: event)
        
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
        
        if optionKeyDown {      // optionKey + mouse click = stop rotation
            paceRotate = CGPoint()
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        updateModifierKeyFlags(event)
        
        var npt = flippedYCoord(event.locationInWindow)
        npt.x -= pt.x
        npt.y -= pt.y
        
        if optionKeyDown {      // optionKey + mouse drag = set rotation speed & direction
            updateRotationSpeedAndDirection(npt)
            return
        }

        wg.focusMovement(npt,1)
    }
    
    override func mouseUp(with event: NSEvent) {
        pt.x = 0
        pt.y = 0
        wg.focusMovement(pt,0)
    }
    
    //MARK: -
    
    func updateRotationSpeedAndDirection(_ pt:NSPoint) {
        let scale:Float = 0.01
        let rRange = SIMD2<Float>(-3,3)
        
        func fClamp(_ v:Float, _ range:SIMD2<Float>) -> Float {
            if v < range.x { return range.x }
            if v > range.y { return range.y }
            return v
        }
        
        paceRotate.x = CGFloat(fClamp(Float(pt.x) * scale, rRange))
        paceRotate.y = -CGFloat(fClamp(Float(pt.y) * scale, rRange))
    }
}
