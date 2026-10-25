import SwiftUI
import CryptoKit

struct LaunchError: LocalizedError { var message: String; var errorDescription: String? { message } }
actor Engine {
    let root: URL
    init(root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("GlassCraft")) { self.root = root }
    var running: Process?
    func folder(_ name: String) throws -> URL { let p=root.appendingPathComponent(name); try FileManager.default.createDirectory(at:p,withIntermediateDirectories:true); return p }
    func fetch(_ url: String) async throws -> Data {
        guard let u=URL(string:url),u.scheme == "https" else { throw LaunchError(message:"无效下载地址") }
        var req=URLRequest(url:u); req.timeoutInterval=90; req.setValue("GlassCraft/0.2 (Aaron-CNSD/GlassCraft-iOS)",forHTTPHeaderField:"User-Agent")
        let (data,res)=try await URLSession.shared.data(for:req)
        guard let r=res as? HTTPURLResponse,(200...299).contains(r.statusCode) else { throw LaunchError(message:"下载失败：\(url)") }; return data
    }
    func object(_ url: String) async throws -> [String:Any] { try JSONSerialization.jsonObject(with:await fetch(url)) as? [String:Any] ?? [:] }
    func digest(_ d:Data)->String { Insecure.SHA1.hash(data:d).map{String(format:"%02x",$0)}.joined() }
    func download(_ item:[String:Any],to path:URL) async throws {
        let expected=item["sha1"] as? String
        if let old=try? Data(contentsOf:path), let sha=expected, digest(old)==sha {return}
        guard let u=item["url"] as? String else {throw LaunchError(message:"缺少下载地址")}
        let data=try await fetch(u)
        if let sha=expected,digest(data) != sha {throw LaunchError(message:"下载校验失败，请重试")}
        try FileManager.default.createDirectory(at:path.deletingLastPathComponent(),withIntermediateDirectories:true)
        try data.write(to:path,options:.atomic)
    }
    func run(_ tool:String,_ args:[String]) throws {
        let p=Process();p.executableURL=URL(fileURLWithPath:tool);p.arguments=args
        p.standardOutput=FileHandle.nullDevice;p.standardError=FileHandle.nullDevice;try p.run();p.waitUntilExit()
        if p.terminationStatus != 0 {throw LaunchError(message:"工具执行失败：\(tool)")}
    }
    func java(_ major:Int) async throws -> URL {
        let base=try folder("java/\(major)")
        func findJava()->URL? {
            let list=FileManager.default.enumerator(at:base,includingPropertiesForKeys:nil)
            while let p=list?.nextObject() as? URL {if p.path.hasSuffix("/Contents/Home/bin/java"),FileManager.default.isExecutableFile(atPath:p.path){return p}}
            return nil
        }
        if let j=findJava(){return j}
        #if arch(arm64)
        let arch="aarch64"
        #else
        let arch="x64"
        #endif
        let json=try await fetch("https://api.adoptium.net/v3/assets/latest/\(major)/hotspot?architecture=\(arch)&image_type=jre&os=mac&vendor=eclipse")
        guard let entries=try JSONSerialization.jsonObject(with:json) as? [[String:Any]],let binary=entries.first?["binary"] as? [String:Any],let package=binary["package"] as? [String:Any],let link=package["link"] as? String, let sha=package["checksum"] as? String else {throw LaunchError(message:"未找到适配此 Mac 的 Java \(major)")}
        let data=try await fetch(link)
        guard SHA256.hash(data:data).map({String(format:"%02x",$0)}).joined()==sha else {throw LaunchError(message:"Java 校验失败")}
        let archive=base.appendingPathComponent("runtime.tar.gz");try data.write(to:archive)
        try run("/usr/bin/tar",["-xzf",archive.path,"-C",base.path]);try? FileManager.default.removeItem(at:archive)
        guard let j=findJava() else {throw LaunchError(message:"Java 解压失败")};return j
    }
    func allowed(_ item:[String:Any])->Bool {
        guard let rules=item["rules"] as? [[String:Any]] else{return true}
        var result=false
        for rule in rules {
            if rule["features"] != nil {continue}
            if let os=rule["os"] as? [String:String] {
                if let name=os["name"],name != "osx" {continue}
                if let pattern=os["version"],ProcessInfo.processInfo.operatingSystemVersionString.range(of:pattern,options:.regularExpression)==nil {continue}
                if let arch=os["arch"] {
                    #if arch(arm64)
                    if arch != "aarch64" && arch != "arm64" {continue}
                    #else
                    if arch != "x86_64" && arch != "x64" {continue}
                    #endif
                }
            }
            result=rule["action"] as? String == "allow"
        }
        return result
    }
    func versions() async throws -> [String] {
        let manifest=try await object("https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")
        return (manifest["versions"] as? [[String:Any]] ?? []).compactMap { v in
            guard v["type"] as? String == "release", let id=v["id"] as? String else{return nil}
            let parts=id.split(separator:".").compactMap{Int($0)}
            return parts.count>1 && parts[0]==1 && parts[1]>=19 ? id:nil
        }
    }
    func launch(version:String,name:String,memory:Int,progress:@escaping @Sendable (String)->Void) async throws {
        if let p=running,p.isRunning {throw LaunchError(message:"游戏已在运行，请先关闭游戏")}
        guard name.range(of:"^[A-Za-z0-9_]{3,16}$",options:.regularExpression) != nil else {throw LaunchError(message:"用户名须为 3–16 位英文字母、数字或下划线")}
        progress("读取版本资料…")
        let manifest=try await object("https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")
        guard let entry=(manifest["versions"] as? [[String:Any]])?.first(where:{$0["id"] as? String==version}),let url=entry["url"] as? String else{throw LaunchError(message:"未找到游戏版本")}
        let meta=try await object(url)
        let major=(meta["javaVersion"] as? [String:Any])?["majorVersion"] as? Int ?? 17
        progress("准备 Java \(major)，首次下载需要时间…")
        let runtime=try await java(major)
        let libs=try folder("libraries"),assets=try folder("assets"),game=try folder("instances/\(version)"),natives=try folder("natives/\(version)")
        _=try folder("instances/\(version)/mods");_=try folder("instances/\(version)/shaderpacks")
        guard let client=(meta["downloads"] as? [String:Any])?["client"] as? [String:Any] else {throw LaunchError(message:"缺少游戏文件")}
        let jar=try folder("versions/\(version)").appendingPathComponent("\(version).jar")
        progress("下载并校验游戏文件…");try await download(client,to:jar)
        var classpath=[String]()
        let libraries=meta["libraries"] as? [[String:Any]] ?? []
        for (i,lib) in libraries.enumerated() where allowed(lib) {
            progress("准备依赖 \(i+1)/\(libraries.count)…")
            if let downloads=lib["downloads"] as? [String:Any] {
                if let a=downloads["artifact"] as? [String:Any],let path=a["path"] as? String {
                    let dest=libs.appendingPathComponent(path);try await download(a,to:dest);classpath.append(dest.path)
                }
                if let classifiers=downloads["classifiers"] as? [String:Any],let native=(lib["natives"] as? [String:String])?["osx"],let a=classifiers[native.replacingOccurrences(of:"${arch}",with:"64")] as? [String:Any],let path=a["path"] as? String {
                    let dest=libs.appendingPathComponent(path);try await download(a,to:dest);try run("/usr/bin/ditto",["-xk",dest.path,natives.path])
                }
            }
        }
        guard let index=meta["assetIndex"] as? [String:Any],let indexID=index["id"] as? String else{throw LaunchError(message:"缺少资源索引")}
        let indexFile=assets.appendingPathComponent("indexes/\(indexID).json");try await download(index,to:indexFile)
        let indexJSON=try JSONSerialization.jsonObject(with:Data(contentsOf:indexFile)) as? [String:Any]
        let objects=indexJSON?["objects"] as? [String:[String:Any]] ?? [:]
        try await withThrowingTaskGroup(of:Void.self) { group in
            var count=0
            for item in objects.values {
                guard let hash=item["hash"] as? String,hash.count==40 else{continue}
                let key="\(hash.prefix(2))/\(hash)"
                group.addTask {try await self.download(["url":"https://resources.download.minecraft.net/\(key)","sha1":hash],to:assets.appendingPathComponent("objects/\(key)"))}
                count += 1
                if count>=12 {try await group.next()}
                if count%25==0 {progress("准备音效与资源 \(count)/\(objects.count)…")}
            }
            try await group.waitForAll()
        }
        let uuid=Insecure.MD5.hash(data:Data("OfflinePlayer:\(name)".utf8)).map{String(format:"%02x",$0)}.joined()
        let vars=["auth_player_name":name,"version_name":version,"game_directory":game.path,"assets_root":assets.path,"assets_index_name":indexID,"auth_uuid":uuid,"auth_access_token":"0","user_type":"legacy","version_type":"release","natives_directory":natives.path,"launcher_name":"GlassCraft","launcher_version":"0.2","classpath":(classpath+[jar.path]).joined(separator:":"),"library_directory":libs.path,"classpath_separator":":","clientid":"","auth_xuid":""]
        func expand(_ s:String)->String {var t=s;for (k,v) in vars {t=t.replacingOccurrences(of:"${\(k)}",with:v)};return t}
        func arguments(_ name:String)->[String] {
            let list=(meta["arguments"] as? [String:Any])?[name] as? [Any] ?? []
            return list.flatMap{item->[String] in
                if let s=item as? String{return [expand(s)]}
                guard let rule=item as? [String:Any],allowed(rule) else{return []}
                if let s=rule["value"] as? String{return [expand(s)]}
                return (rule["value"] as? [String] ?? []).map(expand)
            }
        }
        guard let main=meta["mainClass"] as? String else{throw LaunchError(message:"缺少启动入口")}
        let logs=try folder("logs").appendingPathComponent("latest.log");FileManager.default.createFile(atPath:logs.path,contents:Data())
        let handle=try FileHandle(forWritingTo:logs)
        let p=Process();p.executableURL=runtime;p.currentDirectoryURL=game;p.arguments=["-Xmx\(memory)M"]+arguments("jvm")+[main]+arguments("game");p.standardOutput=handle;p.standardError=handle
        try p.run();running=p;progress("游戏已启动。日志：\(logs.path)")
        p.waitUntilExit();try? handle.close();running=nil
        if p.terminationStatus != 0 {throw LaunchError(message:"游戏退出（\(p.terminationStatus)），请查看 logs/latest.log。旧版本的原生依赖可能不支持此 Mac 架构。")}
        progress("游戏已退出")
    }
}
@MainActor final class Model:ObservableObject {
    @Published var versions=["1.21.1","1.20.1"]
    @Published var selected="1.21.1"
    @Published var name=UserDefaults.standard.string(forKey:"player") ?? "Player"
    @Published var memory=4096.0
    @Published var status="离线本地账号 · 先选择版本，再下载启动"
    @Published var busy=false
    let engine=Engine()
    func refresh() {Task{do{let list=try await engine.versions();versions=list;if !list.contains(selected){selected=list.first ?? "1.21.1"}}catch{status="版本列表加载失败：\(error.localizedDescription)"}}}
    func start(){busy=true;UserDefaults.standard.set(name,forKey:"player");Task{do{try await engine.launch(version:selected,name:name,memory:Int(memory)){message in Task{@MainActor in self.status=message}}}catch{status=error.localizedDescription};busy=false}}
    func importFile(shader:Bool){let panel=NSOpenPanel();panel.allowsMultipleSelection=true;panel.canChooseDirectories=false;if panel.runModal() == .OK{Task{do{let target=try await engine.folder("instances/\(selected)/\(shader ? "shaderpacks":"mods")");for file in panel.urls{guard file.pathExtension.lowercased()==(shader ? "zip":"jar") else{throw LaunchError(message:"请选择 \(shader ? "ZIP 光影包":"JAR 模组")")};let dest=target.appendingPathComponent(file.lastPathComponent);if FileManager.default.fileExists(atPath:dest.path){throw LaunchError(message:"已存在同名文件，请先在游戏目录处理")};try FileManager.default.copyItem(at:file,to:dest)};status="导入成功。模组需要另行安装匹配的加载器；当前自动启动仅支持原版。"}catch{status=error.localizedDescription}}}}
}
@main struct GlassCraftApp:App {
    @StateObject var model=Model()
    var body:some Scene{WindowGroup{VStack(alignment:.leading,spacing:20){
        HStack{Text("GLASSCRAFT").font(.system(size:14,weight:.bold,design:.monospaced)).foregroundStyle(.green);Spacer();Text("macOS · 0.2 预览").foregroundStyle(.secondary)}
        Text("把世界装进你的 Mac。").font(.system(size:34,weight:.bold))
        Text("原版下载、自动安装 Java、独立游戏目录与本地账号。").foregroundStyle(.secondary)
        HStack{TextField("本地用户名",text:$model.name).textFieldStyle(.roundedBorder).frame(width:180);Picker("游戏版本",selection:$model.selected){ForEach(model.versions,id:\.self){Text($0)}}}.disabled(model.busy)
        HStack{Text("内存 \(Int(model.memory)) MB");Slider(value:$model.memory,in:2048...8192,step:1024)}.disabled(model.busy)
        HStack{Button(model.busy ? "准备 / 运行中…":"下载并启动游戏"){model.start()}.buttonStyle(.borderedProminent).tint(.green).disabled(model.busy);Button("资源中心"){NSWorkspace.shared.open(URL(string:"https://aarongame.com/glasscraft/#resources")!)}}
        HStack{Button("导入模组 JAR"){model.importFile(shader:false)};Button("导入光影 ZIP"){model.importFile(shader:true)};Button("打开游戏文件夹"){Task{if let dir=try? await model.engine.folder("instances/\(model.selected)"){NSWorkspace.shared.open(dir)}}}}.disabled(model.busy)
        Text(model.status).font(.system(size:12,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading).padding().background(.quaternary,in:RoundedRectangle(cornerRadius:10))
        Text("当前自动启动仅支持原版 1.19+。模组加载器与整合包自动安装尚未完成。光影需兼容的加载器与渲染器。本地账号无法进入要求正版验证的服务器。首次下载可能需较长时间。").font(.caption).foregroundStyle(.secondary)
    }.padding(30).frame(minWidth:700,minHeight:440).onAppear{model.refresh()}}.windowStyle(.titleBar)}
}
