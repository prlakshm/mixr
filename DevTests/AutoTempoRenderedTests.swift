// Actual app-renderer tempo regression. Deterministic, copyright-free audio.
import Foundation
import AVFoundation
let folder=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
// The live path smooths only musical pitch; rate compensation is immediate.
for speed in [0.25, 0.92, 1.0005, 1.12, 4.0, 8.0] {
    for semitones in [-12.0, 0, 2, 12] {
        var fx = ClipEffectSettings(); fx.setPitch(semitones: semitones)
        let t = ClipEffectDSP.targets(for: fx, playbackSpeed: speed, bpm: 120, echoBoost: 0)
        precondition(abs(Double(t.rateNodeRate * t.timePitchRate) - speed) < 1e-6)
        let netPitch = 1200 * log2(Double(t.rateNodeRate)) + Double(t.timePitchBypass ? 0 : t.pitchCents)
        precondition(abs(netPitch - semitones * 100) < 0.01, "Clock compensation must preserve requested pitch, including bypass")
        let liveCompensated = t.musicalPitchCents + t.ratePitchCompensationCents
        precondition(abs(liveCompensated - t.pitchCents) < 0.001)
    }
}
let sr=44100.0
func fixture(bpm:Double,name:String) throws -> URL {
    let duration=66*60/bpm
    let format=AVAudioFormat(standardFormatWithSampleRate:sr,channels:2)!
    let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(duration*sr))!
    buffer.frameLength=buffer.frameCapacity
    for i in 0..<Int(buffer.frameLength) {
        let t=Double(i)/sr, phase=(t.truncatingRemainder(dividingBy:60/bpm))
        let pulse=phase<0.035 ? 0.35*pow(sin(.pi*phase/0.035),2)*sin(2 * .pi*1100*t) : 0
        let harmony=0.008*(sin(2 * .pi*220*t)+0.5*sin(2 * .pi*330*t))
        for channel in 0..<2 { buffer.floatChannelData![channel][i]=Float(pulse+harmony) }
    }
    let url=folder.appendingPathComponent(name+"-source.wav")
    let file=try AVAudioFile(forWriting:url,settings:format.settings)
    try file.write(from:buffer)
    return url
}
let pair=AutoClubTempo.mashupDecision(vocalBPM:93,bedBPM:95)
var reports:[[String:Any]]=[]
for (name,bpm,target,rate,semitones) in [
    ("pair-vocal",93.0,pair.targetBPM,AutoClubTempo.clubHouseLiftRatio(songBPM:93,targetBPM:pair.targetBPM) ?? pair.vocalRatio,0.0),
    ("pair-bed",95.0,pair.targetBPM,pair.bedRatio,0.0),
    ("native-control",93.0,93.0,1.0,0.0),
    // Known bad rate: gate must reject its drift against the intended target.
    ("negative-drift",93.0,104.16,1.11,0.0),
    ("pitch-up",93.0,104.16,1.12,2.0),
    ("slowdown",128.0,117.76,0.92,-1.0)
] {
    let source=try fixture(bpm:bpm,name:name)
    let duration=66*60/bpm/rate
    var clip=MixrClip(id:UUID(),start:0,length:MixrTimeline.units(fromSeconds:duration),playbackSpeed:rate)
    clip.effects.setPitch(semitones: semitones)
    let track=MixrTrack(id:UUID(),title:name,artist:"Copyright-free regression",duration:"--:--",durationSeconds:66*60/bpm,bpm:Int(bpm),key:"A",color:.pink,volume:0.5,isMuted:false,url:source,artworkData:nil,clips:[clip])
    let url=try MixrExportRenderer.export(tracks:[track],projectName:"tempo-regression-"+UUID().uuidString,projectBPM:Int(target.rounded()))
    let dest=folder.appendingPathComponent(name+".m4a")
    if FileManager.default.fileExists(atPath:dest.path) { try FileManager.default.removeItem(at:dest) }
    try FileManager.default.moveItem(at:url,to:dest)
    reports.append(["name":name,"bpm":bpm,"target":target,"rate":rate,"path":dest.path,"negative_control":name=="negative-drift","expected_pitch_semitones":semitones])
    print("RENDERED \(name)")
}
try JSONSerialization.data(withJSONObject:reports,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("renders.json"))

print("TEMPO_RENDER_DONE cases=\(reports.count)")
