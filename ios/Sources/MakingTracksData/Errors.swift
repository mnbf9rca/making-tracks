import Foundation

public enum AppDatabaseError: Error, Equatable {
    case databaseFromNewerAppVersion(unknown: Set<String>)
    case unreadableDatabase
    case invalidListName
    case systemListIsProtected
}
