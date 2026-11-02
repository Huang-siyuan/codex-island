import Foundation
import Testing
@testable import CodexIslandCore
@testable import CodexIslandApp

private func ipc(_ json: String) throws -> IPCValue {
    try JSONDecoder().decode(IPCValue.self, from: Data(json.utf8))
}

@Test func questionStreamAppliesRequestPatchesAndRejectsGaps() throws {
    var stream = CodexConversationStream()
    try stream.receive(change: ipc(#"{"type":"snapshot","revision":1,"conversationState":{"requests":[]}}"#), ownerID: "owner")
    try stream.receive(change: ipc(#"{"type":"patches","baseRevision":1,"revision":2,"patches":[{"op":"add","path":["requests",0],"value":{"id":23,"method":"item/tool/requestUserInput","params":{"threadId":"thread","questions":[{"id":"color","header":"Color","question":"Which color?","isOther":false,"options":[{"label":"Blue","description":"Cool"}]}]}}}]}"#), ownerID: "owner")
    let question = try #require(stream.questions(threadID: "thread").first)
    #expect(question.validates(["color": "Blue"]))
    #expect(!question.validates(["color": "Green"]))
    #expect(!question.validates(["color": " "]))
    #expect(stream.questions(threadID: "other").isEmpty)
    #expect(throws: CodexLocalError.self) {
        try stream.receive(change: ipc(#"{"type":"patches","baseRevision":0,"revision":3,"patches":[]}"#), ownerID: "owner")
    }
    #expect(stream.questions(threadID: "thread").count == 1)
    try stream.receive(change: ipc(#"{"type":"patches","baseRevision":2,"revision":3,"patches":[{"op":"remove","path":["requests",0]}]}"#), ownerID: "owner")
    #expect(stream.questions(threadID: "thread").isEmpty)
}

@Test func desktopAnswersOriginalRequestAndWaitsForAuthoritativeRemoval() async throws {
    let root = URL(fileURLWithPath: "/tmp/ci-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: root.appendingPathComponent("ipc"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let server = Process()
    server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    server.arguments = ["-c", #"""
import json,socket,struct,sys,time
s=socket.socket(socket.AF_UNIX);s.bind(sys.argv[1]);s.listen();s.settimeout(10)
c,_=s.accept();c.settimeout(5)
def take(n):
 b=b''
 while len(b)<n:
  d=c.recv(n-len(b))
  if not d: raise EOFError()
  b+=d
 return b
def read():return json.loads(take(struct.unpack('<I',take(4))[0]))
def send(x):
 b=json.dumps(x).encode();f=struct.pack('<I',len(b))+b
 c.sendall(f[:2]);time.sleep(.005);c.sendall(f[2:])
x=read();send({'type':'response','requestId':x['requestId'],'result':{'clientId':'island'}})
x=read();assert x['params']['following'] and x['params']['conversationId']=='thread'
request={'id':42,'method':'item/tool/requestUserInput','params':{'threadId':'thread','questions':[{'id':'choice','header':'Choice','question':'Choose','options':[{'label':'One','description':'First'}]}]}}
def change(value):send({'type':'broadcast','method':'thread-stream-state-changed','version':11,'sourceClientId':'owner','params':{'hostId':'local','conversationId':'thread','change':value}})
change({'type':'snapshot','revision':1,'conversationState':{'requests':[request]}})
x=read();assert x['targetClientId']=='owner' and x['method']=='thread-follower-submit-user-input'
assert x['params']=={'conversationId':'thread','requestId':42,'response':{'answers':{'choice':{'answers':['One']}}}}
send({'type':'response','requestId':x['requestId'],'resultType':'success','result':{'ok':True}})
time.sleep(.2)
change({'type':'patches','baseRevision':1,'revision':2,'patches':[{'op':'remove','path':['requests',0]}]})
time.sleep(.5)
c.close();s.close()
"""#, root.appendingPathComponent("ipc/ipc.sock").path]
    try server.run()
    defer { if server.isRunning { server.terminate() }; server.waitUntilExit() }
    for _ in 0..<100 where !FileManager.default.fileExists(atPath: root.appendingPathComponent("ipc/ipc.sock").path) {
        try await Task.sleep(for: .milliseconds(10))
    }
    let client = CodexDesktopClient(codexHome: root)
    var requests: [CodexQuestionRequest] = []
    for _ in 0..<20 {
        requests = await client.refresh(threadIDs: ["thread"])
        if !requests.isEmpty { break }
        try await Task.sleep(for: .milliseconds(50))
    }
    let request = try #require(requests.first)
    let start = Date()
    try await client.answer(request, answers: ["choice": "One"])
    #expect(Date().timeIntervalSince(start) >= 0.2)
    #expect(await client.refresh(threadIDs: ["thread"]).isEmpty)
    await #expect(throws: CodexLocalError.self) { try await client.answer(request, answers: ["choice": "One"]) }
    await client.close()
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["CODEX_ISLAND_LIVE_TEST"] == "1"))
func desktopLiveReadOnlyProtocolProbe() async throws {
    let client = CodexDesktopClient()
    _ = await client.refresh(threadIDs: [])
    #expect(await client.isConnected)
    await client.close()
    let executable = try #require(ProcessInfo.processInfo.environment["CODEX_ISLAND_CLI"])
    let response = try await SubscriptionQuotaReader.read(executable: URL(fileURLWithPath: executable))
    #expect(!response.limits.isEmpty)
}

@MainActor
@Test func answerFormPreventsDuplicateSubmissionsAndClearsConfirmedDrafts() async throws {
    let model = IslandViewModel(focusRouter: FocusRouter(), soundPreferenceStore: SoundPreferenceStore())
    let questions = try JSONDecoder().decode([CodexQuestion].self, from: Data(#"[{"id":"answer","header":"Answer","question":"What next?"}]"#.utf8))
    let request = CodexQuestionRequest(threadID: "thread", requestID: .string("request"), ownerID: "owner", questions: questions)
    model.applyQuestions([request])
    model.activeQuestionID = request.id
    model.setAnswer("Continue", questionID: "answer", requestID: request.id)
    var calls = 0
    var confirmation: CheckedContinuation<Void, Never>?
    model.onQuestionAnswer = { _, answers in
        calls += 1
        #expect(answers == ["answer": "Continue"])
        await withCheckedContinuation { confirmation = $0 }
    }
    model.submitAnswer(request)
    model.submitAnswer(request)
    while confirmation == nil { await Task.yield() }
    #expect(calls == 1)
    #expect(model.submittingQuestionID == request.id)
    #expect(model.pendingQuestions == [request])
    confirmation?.resume()
    while model.submittingQuestionID != nil { await Task.yield() }
    #expect(model.pendingQuestions.isEmpty)
    #expect(model.questionDrafts.isEmpty)
    #expect(model.activeQuestionID == nil)
}

@MainActor
@Test func disconnectedQuestionClearsDraftWithoutSubmitting() throws {
    let model = IslandViewModel(focusRouter: FocusRouter(), soundPreferenceStore: SoundPreferenceStore())
    let questions = try JSONDecoder().decode([CodexQuestion].self, from: Data(#"[{"id":"answer","header":"Answer","question":"What next?"}]"#.utf8))
    let request = CodexQuestionRequest(threadID: "thread", requestID: .number(1), ownerID: "owner", questions: questions)
    model.applyQuestions([request])
    model.activeQuestionID = request.id
    model.setAnswer("Private draft", questionID: "answer", requestID: request.id)
    model.applyQuestions([])
    #expect(model.questionDrafts.isEmpty)
    #expect(model.activeQuestionID == nil)
    #expect(model.submittingQuestionID == nil)
}
