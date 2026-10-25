import SwiftUI
import CryptoKit
import UniformTypeIdentifiers

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
    func safePath(_ path:String) throws -> String {
        let parts=path.split(separator:"/",omittingEmptySubsequences:false)
        guard !path.isEmpty,!path.hasPrefix("/"),!path.contains("\\"),!path.contains(":"),!path.contains("\0"),!parts.contains(".."),!parts.contains(".") else {throw LaunchError(message:"整合包包含不安全路径")}
        return path
    }
    func capture(_ args:[String]) throws -> String {
        let p=Process(),pipe=Pipe();p.executableURL=URL(fileURLWithPath:"/usr/bin/zipinfo");p.arguments=args;p.standardOutput=pipe;p.standardError=FileHandle.nullDevice
        try p.run();let data=pipe.fileHandleForReading.readDataToEndOfFile();p.waitUntilExit()
        guard p.terminationStatus==0,let result=String(data:data,encoding:.utf8) else{throw LaunchError(message:"无法读取整合包 ZIP")};return result
    }
    func packList() throws -> [[String:String]] {
        let dir=try folder("packs")
        return try FileManager.default.contentsOfDirectory(at:dir,includingPropertiesForKeys:nil).filter{$0.pathExtension=="json"}.compactMap{url in
            guard let data=try? Data(contentsOf:url),let obj=try? JSONSerialization.jsonObject(with:data) as? [String:Any],let id=obj["id"] as? String,let name=obj["name"] as? String,let mc=obj["minecraft"] as? String else{return nil}
            return ["id":id,"name":name,"minecraft":mc]
        }.sorted{($0["name"] ?? "")<($1["name"] ?? "")}
    }
    func gameFolder(version:String,packID:String?) throws -> URL {
        if let id=packID {guard UUID(uuidString:id) != nil else{throw LaunchError(message:"无效整合包配置")};return try folder("instances/packs/\(id)")}
        return try folder("instances/\(version)")
    }
    func importPack(_ archive:URL,progress:@escaping @Sendable(String)->Void) async throws -> String {
        let fm=FileManager.default
        guard archive.pathExtension.lowercased()=="mrpack",(try archive.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0)<536870912 else{throw LaunchError(message:"请选择小于 512 MB 的 .mrpack 文件；不支持 CurseForge ZIP")}
        progress("检查整合包…")
        let listing=try capture(["-1",archive.path]).split(separator:"\n").map(String.init)
        guard listing.count<30000,Set(listing).count==listing.count else{throw LaunchError(message:"整合包条目过多或重复")}
        for name in listing {_ = try safePath(name)}
        let details=try capture(["-l",archive.path]);var total:Int64=0
        for line in details.split(separator:"\n") {
            if line.hasPrefix("l"){throw LaunchError(message:"整合包不允许符号链接")}
            if line.hasPrefix("-") || line.hasPrefix("d") {let fields=line.split(whereSeparator:{$0==" " || $0=="\t"});if fields.count>3,let size=Int64(fields[3]){total += size}}
        }
        guard total<2147483648 else{throw LaunchError(message:"整合包解压大小超过 2 GB")}
        let id=UUID().uuidString,stage=try folder("staging/\(id)"),game=stage.appendingPathComponent("game")
        defer{try? fm.removeItem(at:stage)}
        let unpack=stage.appendingPathComponent("archive");try fm.createDirectory(at:unpack,withIntermediateDirectories:true)
        try run("/usr/bin/ditto",["-xk",archive.path,unpack.path])
        let indexData=try Data(contentsOf:unpack.appendingPathComponent("modrinth.index.json"))
        guard let index=try JSONSerialization.jsonObject(with:indexData) as? [String:Any],index["formatVersion"] as? Int==1,index["game"] as? String=="minecraft",let deps=index["dependencies"] as? [String:String],let mc=deps["minecraft"],let files=index["files"] as? [[String:Any]] else{throw LaunchError(message:"不支持的 mrpack 清单")}
        let parts=mc.split(separator:".").compactMap{Int($0)}
        guard parts.count>=2,parts[0]==1,parts[1]>=19 else{throw LaunchError(message:"目前整合包仅支持 Minecraft 1.19+")}
        guard Set(deps.keys).isSubset(of:["minecraft","fabric-loader","quilt-loader"]),!(deps["fabric-loader"] != nil && deps["quilt-loader"] != nil) else{throw LaunchError(message:"目前支持 Fabric、Quilt 或原版 mrpack；暂不支持 Forge/NeoForge")}
        var profile:[String:Any]=[:]
        if let loader=deps["fabric-loader"] ?? deps["quilt-loader"] {
            guard loader.range(of:"^[A-Za-z0-9._+-]+$",options:.regularExpression) != nil else{throw LaunchError(message:"无效加载器版本")}
            progress("准备整合包加载器…")
            let base=deps["fabric-loader"] != nil ? "https://meta.fabricmc.net/v2":"https://meta.quiltmc.org/v3"
            profile=try await object("\(base)/versions/loader/\(mc)/\(loader)/profile/json")
            guard profile["mainClass"] is String,profile["libraries"] is [[String:Any]] else{throw LaunchError(message:"加载器配置无效")}
        }
        try fm.createDirectory(at:game,withIntermediateDirectories:true)
        guard files.count<30000 else{throw LaunchError(message:"整合包文件过多")}
        var seen=Set<String>()
        for (i,file) in files.enumerated() {
            let client=(file["env"] as? [String:String])?["client"] ?? "required"
            if client=="unsupported" || client=="optional" {continue}
            guard client=="required",let path=file["path"] as? String,let hashes=file["hashes"] as? [String:String],let urls=file["downloads"] as? [String],!urls.isEmpty else{throw LaunchError(message:"资源条目无效")}
            _=try safePath(path);guard seen.insert(path).inserted else{throw LaunchError(message:"资源路径重复")}
            progress("下载整合包文件 \(i+1)/\(files.count)…")
            var verified:Data?
            for link in urls {
                guard let u=URL(string:link),u.scheme=="https",let host=u.host,["cdn.modrinth.com","github.com","raw.githubusercontent.com","gitlab.com"].contains(host) else{continue}
                do{let data=try await fetch(link)
                    if let size=file["fileSize"] as? Int,data.count != size {continue}
                    if let sha=hashes["sha512"],SHA512.hash(data:data).map({String(format:"%02x",$0)}).joined()==sha {verified=data;break}
                    if hashes["sha512"]==nil,let sha=hashes["sha1"],digest(data)==sha {verified=data;break}
                }catch{continue}
            }
            guard let data=verified else{throw LaunchError(message:"下载或校验失败：\(path)")}
            let dest=game.appendingPathComponent(path);try fm.createDirectory(at:dest.deletingLastPathComponent(),withIntermediateDirectories:true);try data.write(to:dest,options:.atomic)
        }
        for folder in ["overrides","client-overrides"] {
            let source=unpack.appendingPathComponent(folder)
            if let items=fm.enumerator(at:source,includingPropertiesForKeys:[.isDirectoryKey,.isSymbolicLinkKey]) {
                while let item=items.nextObject() as? URL {
                    let values=try item.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey]);guard values.isSymbolicLink != true else{throw LaunchError(message:"不允许符号链接")}
                    let rel=String(item.path.dropFirst(source.path.count+1));_=try safePath(rel);let dest=game.appendingPathComponent(rel)
                    if values.isDirectory==true {try fm.createDirectory(at:dest,withIntermediateDirectories:true)}
                    else{try fm.createDirectory(at:dest.deletingLastPathComponent(),withIntermediateDirectories:true);if fm.fileExists(atPath:dest.path){try fm.removeItem(at:dest)};try fm.copyItem(at:item,to:dest)}
                }
            }
        }
        let final=try gameFolder(version:mc,packID:id);try fm.removeItem(at:final);try fm.moveItem(at:game,to:final)
        do {let record:[String:Any]=["id":id,"name":index["name"] as? String ?? archive.deletingPathExtension().lastPathComponent,"minecraft":mc,"loaderProfile":profile]
            let dest=try folder("packs").appendingPathComponent("\(id).json");try JSONSerialization.data(withJSONObject:record).write(to:dest,options:.atomic)
        }catch{try? fm.removeItem(at:final);throw error}
        progress("整合包已导入。可选客户端模组默认跳过。请选择整合包后启动。")
        return id
    }
    func launch(version:String,name:String,memory:Int,packID:String?=nil,progress:@escaping @Sendable (String)->Void) async throws {
        if let p=running,p.isRunning {throw LaunchError(message:"游戏已在运行，请先关闭游戏")}
        guard name.range(of:"^[A-Za-z0-9_]{3,16}$",options:.regularExpression) != nil else {throw LaunchError(message:"用户名须为 3–16 位英文字母、数字或下划线")}
        progress("读取版本资料…")
        let manifest=try await object("https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")
        guard let entry=(manifest["versions"] as? [[String:Any]])?.first(where:{$0["id"] as? String==version}),let url=entry["url"] as? String else{throw LaunchError(message:"未找到游戏版本")}
        var meta=try await object(url)
        if let id=packID {
            guard UUID(uuidString:id) != nil else{throw LaunchError(message:"无效整合包配置")}
            let data=try Data(contentsOf:root.appendingPathComponent("packs/\(id).json"))
            guard let record=try JSONSerialization.jsonObject(with:data) as? [String:Any],record["minecraft"] as? String==version else{throw LaunchError(message:"整合包游戏版本不匹配")}
            let profile=record["loaderProfile"] as? [String:Any] ?? [:]
            if let main=profile["mainClass"] as? String {meta["mainClass"]=main}
            let libs=(profile["libraries"] as? [[String:Any]] ?? [])+(meta["libraries"] as? [[String:Any]] ?? [])
            var names=Set<String>();meta["libraries"]=libs.filter {names.insert($0["name"] as? String ?? UUID().uuidString).inserted}
            var args=meta["arguments"] as? [String:Any] ?? [:]
            for key in ["jvm","game"] {args[key]=(args[key] as? [Any] ?? [])+((profile["arguments"] as? [String:Any])?[key] as? [Any] ?? [])}
            meta["arguments"]=args
        }
        let major=(meta["javaVersion"] as? [String:Any])?["majorVersion"] as? Int ?? 17
        progress("准备 Java \(major)，首次下载需要时间…")
        let runtime=try await java(major)
        let libs=try folder("libraries"),assets=try folder("assets"),game=try gameFolder(version:version,packID:packID),natives=try folder("natives/\(version)")

        guard let client=(meta["downloads"] as? [String:Any])?["client"] as? [String:Any] else {throw LaunchError(message:"缺少游戏文件")}
        let jar=try folder("versions/\(version)").appendingPathComponent("\(version).jar")
        progress("下载并校验游戏文件…");try await download(client,to:jar)
        var classpath=[String]()
        let libraries=meta["libraries"] as? [[String:Any]] ?? []
        for (i,lib) in libraries.enumerated() where allowed(lib) {
            progress("准备依赖 \(i+1)/\(libraries.count)…")
            var downloads=lib["downloads"] as? [String:Any]
            if downloads==nil,let name=lib["name"] as? String {
                let c=name.split(separator:":").map(String.init)
                guard c.count==3 else{throw LaunchError(message:"不支持的加载器依赖")}
                let path=c[0].replacingOccurrences(of:".",with:"/")+"/"+c[1]+"/"+c[2]+"/"+c[1]+"-"+c[2]+".jar"
                let base=lib["url"] as? String ?? "https://libraries.minecraft.net/"
                downloads=["artifact":["path":path,"url":base+(base.hasSuffix("/") ? "":"/")+path]]
            }
            if let downloads=downloads {
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
    @Published var packs=[[String:String]]()
    @Published var packID=""
    @Published var busy=false
    let engine=Engine()
    func refresh() {Task{packs=(try? await engine.packList()) ?? [];do{let list=try await engine.versions();versions=list;if !list.contains(selected){selected=list.first ?? "1.21.1"}}catch{status="版本列表加载失败：\(error.localizedDescription)"}}}
    func start(){busy=true;UserDefaults.standard.set(name,forKey:"player");Task{do{try await engine.launch(version:selected,name:name,memory:Int(memory),packID:packID.isEmpty ? nil:packID){message in Task{@MainActor in self.status=message}}}catch{status=error.localizedDescription};busy=false}}
    func importModpack(){let panel=NSOpenPanel();panel.allowsMultipleSelection=false;panel.canChooseDirectories=false;panel.allowedContentTypes=[UTType(filenameExtension:"mrpack") ?? .archive];guard panel.runModal() == .OK,let url=panel.url else{return};busy=true;Task{do{let id=try await engine.importPack(url){message in Task{@MainActor in self.status=message}};packs=try await engine.packList();packID=id;selected=packs.first(where:{$0["id"]==id})?["minecraft"] ?? selected}catch{status=error.localizedDescription};busy=false}}
    func importFile(shader:Bool){let panel=NSOpenPanel();panel.allowsMultipleSelection=true;panel.canChooseDirectories=false;if panel.runModal() == .OK{Task{do{let target=try await engine.gameFolder(version:selected,packID:packID.isEmpty ? nil:packID).appendingPathComponent(shader ? "shaderpacks":"mods");try FileManager.default.createDirectory(at:target,withIntermediateDirectories:true);for file in panel.urls{guard file.pathExtension.lowercased()==(shader ? "zip":"jar") else{throw LaunchError(message:"请选择 \(shader ? "ZIP 光影包":"JAR 模组")")};let dest=target.appendingPathComponent(file.lastPathComponent);if FileManager.default.fileExists(atPath:dest.path){throw LaunchError(message:"已存在同名文件，请先在游戏目录处理")};try FileManager.default.copyItem(at:file,to:dest)};status="导入成功。模组需要另行安装匹配的加载器；当前自动启动仅支持原版。"}catch{status=error.localizedDescription}}}}
}
@main struct GlassCraftApp:App {
    @StateObject var model=Model()
    var body:some Scene{WindowGroup{VStack(alignment:.leading,spacing:20){
        HStack{Text("GLASSCRAFT").font(.system(size:14,weight:.bold,design:.monospaced)).foregroundStyle(.green);Spacer();Text("macOS · 0.3 预览").foregroundStyle(.secondary)}
        Text("把世界装进你的 Mac。").font(.system(size:34,weight:.bold))
        Text("原版下载、自动安装 Java、独立游戏目录与本地账号。").foregroundStyle(.secondary)
        HStack{TextField("本地用户名",text:$model.name).textFieldStyle(.roundedBorder).frame(width:180);Picker("游戏版本",selection:$model.selected){ForEach(model.versions,id:\.self){Text($0)}}}.disabled(model.busy || !model.packID.isEmpty)
        HStack{Picker("启动配置",selection:$model.packID){Text("原版").tag("");ForEach(model.packs,id:\.self){pack in Text(pack["name"] ?? "整合包").tag(pack["id"] ?? "")}}.onChange(of:model.packID){id in if let pack=model.packs.first(where:{$0["id"]==id}){model.selected=pack["minecraft"] ?? model.selected}};Button("导入整合包 .mrpack"){model.importModpack()}}.disabled(model.busy)
        HStack{Text("内存 \(Int(model.memory)) MB");Slider(value:$model.memory,in:2048...8192,step:1024)}.disabled(model.busy)
        HStack{Button(model.busy ? "准备 / 运行中…":"下载并启动游戏"){model.start()}.buttonStyle(.borderedProminent).tint(.green).disabled(model.busy);Button("资源中心"){NSWorkspace.shared.open(URL(string:"https://aarongame.com/glasscraft/#resources")!)}}
        HStack{Button("导入模组 JAR"){model.importFile(shader:false)};Button("导入光影 ZIP"){model.importFile(shader:true)};Button("打开游戏文件夹"){Task{if let dir=try? await model.engine.gameFolder(version:model.selected,packID:model.packID.isEmpty ? nil:model.packID){NSWorkspace.shared.open(dir)}}}}.disabled(model.busy)
        Text(model.status).font(.system(size:12,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading).padding().background(.quaternary,in:RoundedRectangle(cornerRadius:10))
        Text("支持原版及 Fabric / Quilt .mrpack 整合包（1.19+）；暂不支持 Forge、NeoForge 或 CurseForge ZIP。光影需兼容的加载器与渲染器。本地账号无法进入要求正版验证的服务器。首次下载可能需较长时间。").font(.caption).foregroundStyle(.secondary)
    }.padding(30).frame(minWidth:700,minHeight:440).onAppear{model.refresh()}}.windowStyle(.titleBar)}
}
