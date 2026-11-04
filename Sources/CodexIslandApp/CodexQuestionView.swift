import CodexIslandCore
import SwiftUI

struct CodexQuestionView: View {
    @ObservedObject var viewModel: IslandViewModel
    let request: CodexQuestionRequest
    let language: InterfaceLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if viewModel.activeQuestionID != request.id {
                Button(language.text("Answer in Island", "在岛上回答")) {
                    viewModel.activeQuestionID = request.id
                }
                .accessibilityIdentifier("question.open")
            } else {
                ForEach(request.questions) { question in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(question.header).font(IslandTypography.section)
                        Text(question.question).font(IslandTypography.body).textSelection(.enabled)
                        ForEach(question.options ?? []) { option in
                            Button {
                                viewModel.setAnswer(option.label, questionID: question.id, requestID: request.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(option.label).font(IslandTypography.control)
                                    if !option.description.isEmpty {
                                        Text(option.description).font(IslandTypography.caption).foregroundStyle(IslandPalette.subtitle)
                                    }
                                }
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(IslandButtonStyle(isSelected: viewModel.questionDrafts[request.id]?[question.id] == option.label, isMultiline: true))
                            .accessibilityAddTraits(viewModel.questionDrafts[request.id]?[question.id] == option.label ? .isSelected : [])
                        }
                        if (question.options ?? []).isEmpty || question.isOther != false {
                            if question.isSecret == true {
                                SecureField(language.text("Your answer", "输入回答"), text: answer(question.id))
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                TextField(language.text("Your answer", "输入回答或补充说明"), text: answer(question.id), axis: .vertical)
                                    .lineLimit(1...5)
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityLabel(question.question)
                            }
                        }
                    }
                }
                if viewModel.questionErrorID == request.id {
                    Text(language.text("Could not confirm the answer. Check this conversation in Codex before retrying.", "未能确认回答成功，请先在 Codex 查看该会话再重试。"))
                        .font(IslandTypography.caption).foregroundStyle(IslandPalette.error)
                }
                HStack {
                    Button(language.text("Submit answer", "提交回答")) { viewModel.submitAnswer(request) }
                        .disabled(!request.validates(viewModel.questionDrafts[request.id] ?? [:]) || viewModel.submittingQuestionID != nil)
                        .accessibilityIdentifier("question.submit")
                    if viewModel.submittingQuestionID == request.id { ProgressView().controlSize(.small) }
                    Spacer()
                    Button(language.text("Close", "收起")) { viewModel.activeQuestionID = nil }
                        .disabled(viewModel.submittingQuestionID == request.id)
                }
            }
        }
        .buttonStyle(IslandButtonStyle())
        .disabled(viewModel.submittingQuestionID == request.id)
        .padding(IslandLayout.cardPadding)
        .modifier(IslandSurface(highlighted: true))
    }

    private func answer(_ questionID: String) -> Binding<String> {
        Binding(get: { viewModel.questionDrafts[request.id]?[questionID] ?? "" }, set: {
            viewModel.setAnswer($0, questionID: questionID, requestID: request.id)
        })
    }
}
