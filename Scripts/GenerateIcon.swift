import AppKit
let root = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
var images: [[String:String]] = []
for size in [16, 32, 128, 256, 512] {
 for scale in [1, 2] {
  let pixels = size * scale
  let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
  let p = CGFloat(pixels)
  let shape = NSBezierPath(roundedRect: NSRect(x: p*0.05, y:p*0.05, width:p*0.9, height:p*0.9), xRadius:p*0.21, yRadius:p*0.21)
  NSGradient(starting:NSColor(srgbRed:0.08, green:0.18, blue:0.22, alpha:1), ending:NSColor(srgbRed:0.04, green:0.08, blue:0.13, alpha:1))!.draw(in:shape, angle:60)
  let bird = NSImage(systemSymbolName:"bird.fill", accessibilityDescription:nil)!.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize:p*0.55, weight:.medium).applying(.init(paletteColors: [NSColor(srgbRed:0.4,green:0.92,blue:0.76,alpha:1)])))!
  let rect = NSRect(x:p*0.22,y:p*0.25,width:p*0.56,height:p*0.56)
  bird.draw(in:rect)
  NSColor(srgbRed:0.4,green:0.92,blue:0.76,alpha:1).setFill()
  for i in 0..<3 { NSBezierPath(roundedRect:NSRect(x:p*(0.28+Double(i)*0.16),y:p*0.18,width:p*0.11,height:p*0.035),xRadius:p*0.017,yRadius:p*0.017).fill() }
  NSGraphicsContext.restoreGraphicsState()
  let data = bitmap.representation(using:.png,properties:[:])!
  let name = "icon_\(size)@\(scale)x.png"
  try data.write(to:root.appendingPathComponent(name))
  images.append(["idiom":"mac","size":"\(size)x\(size)","scale":"\(scale)x","filename":name])
 }
}
try JSONSerialization.data(withJSONObject:["images":images,"info":["author":"xcode","version":1]],options:.prettyPrinted).write(to:root.appendingPathComponent("Contents.json"))
