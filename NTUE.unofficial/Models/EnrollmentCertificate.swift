import Foundation

/// 在學證明（a02280）— parsed directly from the server-rendered page.
struct EnrollmentCertificate {
    var studentId = ""
    var name = ""
    var year = ""
    var semester = ""

    // 中文
    var birthday = ""
    var department = ""
    var grade = ""
    var office = ""
    var chinesePdfPath = ""

    // English
    var englishName = ""
    var englishDepartment = ""
    var admissionTerm = ""
    var classTypeStatement = ""
    var englishPdfPath = ""

    var isEmpty: Bool { studentId.isEmpty && name.isEmpty }
}
