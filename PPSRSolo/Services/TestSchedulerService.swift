import Foundation

class TestSchedulerService {
    static let shared = TestSchedulerService()
    private let key = "testSchedules"
    private(set) var schedules: [TestSchedule] = []
    var onScheduleTriggered: ((TestSchedule) -> Void)?
    private var monitorTask: Task<Void, Never>?

    private init() {
        loadSchedules()
    }

    func startMonitoring() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self else { return }
                let now = Date()
                let due = self.schedules.filter { $0.scheduledDate <= now }
                for schedule in due {
                    self.onScheduleTriggered?(schedule)
                    self.removeSchedule(schedule)
                }
            }
        }
    }

    func addSchedule(_ schedule: TestSchedule) {
        schedules.append(schedule)
        saveSchedules()
    }

    func removeSchedule(_ schedule: TestSchedule) {
        schedules.removeAll { $0.id == schedule.id }
        saveSchedules()
    }

    private func loadSchedules() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let loaded = try? JSONDecoder().decode([TestSchedule].self, from: data) else { return }
        schedules = loaded
    }

    private func saveSchedules() {
        if let data = try? JSONEncoder().encode(schedules) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
