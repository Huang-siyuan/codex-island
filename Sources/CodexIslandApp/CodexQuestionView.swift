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
                                select(option.label, question: question)
                            } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    if question.multiSelect == true {
                                        Image(systemName: isSelected(option.label, question: question) ? "checkmark.square.fill" : "square")
                                            .foregroundStyle(isSelected(option.label, question: question) ? IslandPalette.accent : IslandPalette.subtitle)
                                            .accessibilityHidden(true)
                                    }
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(option.label).font(IslandTypography.control)
                                        if !option.description.isEmpty {
                                            Text(option.description).font(IslandTypography.caption).foregroundStyle(IslandPalette.subtitle)
                                        }
                                    }
                                }
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(IslandButtonStyle(isSelected: isSelected(option.label, question: question), isMultiline: true))
                            .accessibilityAddTraits(isSelected(option.label, question: question) ? .isSelected : [])
                        }
                        if (question.options ?? []).isEmpty || question.isOther != false {
                            if question.isSecret == true {
                                SecureField(language.text("Your answer", "输入回答"), text: answer(question))
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                TextField(language.text("Your answer", "输入回答或补充说明"), text: answer(question), axis: .vertical)
                                    .lineLimit(1...5)
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityLabel(question.question)
                            }
                        }
                    }
                }
                if viewModel.questionErrorID == request.id {
                    Text(language.text("Could not confirm the answer. Check this conversation in \(request.provider.displayName) before retrying.", "未能确认回答成功，请先在 \(request.provider.displayName) 查看该会话再重试。"))
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

    private func multiple(_ question: CodexQuestion) -> DeepSeekMultipleAnswer {
        let raw = viewModel.questionDrafts[request.id]?[question.id] ?? ""
        return (try? JSONDecoder().decode(DeepSeekMultipleAnswer.self, from: Data(raw.utf8))) ?? .init()
    }

    private func save(_ value: DeepSeekMultipleAnswer, question: CodexQuestion) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        viewModel.setAnswer(String(decoding: data, as: UTF8.self), questionID: question.id, requestID: request.id)
    }

    private func isSelected(_ label: String, question: CodexQuestion) -> Bool {
        question.multiSelect == true ? multiple(question).selected.contains(label)
            : viewModel.questionDrafts[request.id]?[question.id] == label
    }

    private func select(_ label: String, question: CodexQuestion) {
        if question.multiSelect == true {
            var value = multiple(question)
            if value.selected.contains(label) { value.selected.removeAll { $0 == label } }
            else { value.selected.append(label) }
            save(value, question: question)
        } else {
            viewModel.setAnswer(label, questionID: question.id, requestID: request.id)
        }
    }

    private func answer(_ question: CodexQuestion) -> Binding<String> {
        Binding(get: {
            question.multiSelect == true ? multiple(question).custom : viewModel.questionDrafts[request.id]?[question.id] ?? ""
        }, set: {
            if question.multiSelect == true {
                var value = multiple(question)
                value.custom = $0
                save(value, question: question)
            } else {
                viewModel.setAnswer($0, questionID: question.id, requestID: request.id)
            }
        })
    }
}
