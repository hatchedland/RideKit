import Foundation
import Testing
@testable import RideKit

@Suite("Friends: group chat")
struct ChatTests {
    let group = UUID()
    let me = UUID()
    let aman = UUID()
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func message(_ seconds: TimeInterval, from sender: UUID? = nil, _ body: String = "hi",
                 id: UUID = UUID(), delivery: ChatMessage.Delivery = .sent) -> ChatMessage {
        ChatMessage(id: id, groupID: group, senderID: sender ?? aman, body: body,
                    sentAt: t0.addingTimeInterval(seconds), delivery: delivery)
    }

    // MARK: Text

    @Test func prepareTrimsAndRejectsBlank() {
        #expect(ChatText.prepare("  Sunday 6 am?\n") == "Sunday 6 am?")
        #expect(ChatText.prepare(" \n\t ") == nil)
        #expect(ChatText.prepare("") == nil)
    }

    @Test func prepareCutsAtTheLimit() {
        let long = String(repeating: "a", count: ChatText.maxLength + 50)
        #expect(ChatText.prepare(long)?.count == ChatText.maxLength)
    }

    @Test func previewIsOneShortLine() {
        #expect(ChatText.preview("Meet at\nMurthal") == "Meet at Murthal")
        let preview = ChatText.preview(String(repeating: "b", count: 200), limit: 10)
        #expect(preview.count == 10)
        #expect(preview.hasSuffix("…"))
    }

    // MARK: Timeline

    @Test func sentMessagesAreInServerOrder() {
        let timeline = ChatTimeline(messages: [message(30), message(10), message(20)])
        #expect(timeline.messages.map(\.sentAt) == [10, 20, 30].map { t0.addingTimeInterval($0) })
        #expect(timeline.newestSentAt == t0.addingTimeInterval(30))
        #expect(timeline.oldestSentAt == t0.addingTimeInterval(10))
    }

    @Test func unsentMessagesStayAtTheBottom() {
        var timeline = ChatTimeline(messages: [message(10)])
        timeline.merge([message(5, from: me, delivery: .sending)])
        timeline.merge([message(20)])
        #expect(timeline.messages.map(\.isPending) == [false, false, true])
        #expect(timeline.pending.count == 1)
        #expect(timeline.newestSentAt == t0.addingTimeInterval(20))
    }

    @Test func serverCopyReplacesThePendingOne() {
        let id = UUID()
        var timeline = ChatTimeline(messages: [message(0, from: me, "on my way", id: id, delivery: .sending)])
        timeline.merge([message(60, from: me, "on my way", id: id)])
        #expect(timeline.messages.count == 1)
        #expect(timeline.messages[0].delivery == .sent)
        #expect(timeline.messages[0].sentAt == t0.addingTimeInterval(60))
    }

    @Test func staleLocalCopyNeverUndoesADeliveredMessage() {
        let id = UUID()
        var timeline = ChatTimeline(messages: [message(60, from: me, id: id)])
        timeline.merge([message(0, from: me, id: id, delivery: .failed)])
        #expect(timeline.messages[0].delivery == .sent)
    }

    @Test func mergingTwiceDoesNotDuplicate() {
        let batch = [message(10), message(20)]
        var timeline = ChatTimeline(messages: batch)
        timeline.merge(batch)
        #expect(timeline.messages.count == 2)
    }

    @Test func deliveryChangesAndRemoval() {
        let id = UUID()
        var timeline = ChatTimeline(messages: [message(10), message(0, from: me, id: id, delivery: .sending)])
        timeline.setDelivery(.failed, for: id)
        #expect(timeline.messages.last?.delivery == .failed)
        timeline.setDelivery(.sent, for: UUID()) // unknown id: no change
        timeline.remove([id])
        #expect(timeline.messages.count == 1)
    }

    @Test func trimmingKeepsNewestSentAndAllPending() {
        var timeline = ChatTimeline(messages: (0..<10).map { message(TimeInterval($0)) })
        timeline.merge([message(100, from: me, delivery: .failed)])
        let kept = timeline.trimmed(to: 3)
        #expect(kept.sent.map(\.sentAt) == [7, 8, 9].map { t0.addingTimeInterval($0) })
        #expect(kept.pending.count == 1)
        #expect(timeline.trimmed(to: 50) == timeline)
    }

    @Test func timelineSurvivesEncoding() throws {
        let timeline = ChatTimeline(messages: [message(1), message(2, from: me, delivery: .sending)])
        let data = try JSONEncoder().encode(timeline)
        #expect(try JSONDecoder().decode(ChatTimeline.self, from: data) == timeline)
    }

    // MARK: Layout

    @Test func layoutAddsDayHeadersAndRuns() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let messages = [
            message(0, from: aman), message(60, from: aman),          // one run
            message(120, from: me),                                   // new sender
            message(120 + ChatLayout.runGap + 1, from: me),           // long pause
            message(86_400, from: me),                                // next day
        ]
        let rows = ChatLayout.rows(messages, calendar: calendar)
        let shape: [String] = rows.map {
            switch $0 {
            case .day: "day"
            case .message(_, let startsRun): startsRun ? "start" : "more"
            }
        }
        #expect(shape == ["day", "start", "more", "start", "start", "day", "start"])
        #expect(Set(rows.map(\.id)).count == rows.count)
    }

    @Test func emptyLayoutHasNoRows() {
        #expect(ChatLayout.rows([]).isEmpty)
    }
}
