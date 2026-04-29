enum TriggerSource: String {
    case functionKey = "fn long-press"
    case fallbackHotKey = "Control+Option+Space"
}

protocol TriggerMonitorDelegate: AnyObject {
    func triggerDidBegin(source: TriggerSource)
    func triggerDidEnd(source: TriggerSource)
    func triggerMonitorStatusDidChange()
}
