PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'PermissionCheckerPermissionSet' LIMIT 1];

List<PermissionSetAssignment> mine = [
    SELECT Id FROM PermissionSetAssignment
    WHERE AssigneeId = :UserInfo.getUserId() AND PermissionSetId = :ps.Id
];
if (mine.isEmpty()) {
    insert new PermissionSetAssignment(AssigneeId = UserInfo.getUserId(), PermissionSetId = ps.Id);
}

Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
String stamp = String.valueOf(Datetime.now().getTime());
User u = new User(
    FirstName = 'Albert', LastName = 'Einstein',
    Alias = 'aeins', Email = 'albert@example.com',
    Username = 'albert.' + stamp + '@wsw.test',
    ProfileId = p.Id, TimeZoneSidKey = 'Asia/Dhaka',
    LocaleSidKey = 'en_US', EmailEncodingKey = 'UTF-8',
    LanguageLocaleKey = 'en_US'
);
insert u;
System.debug(LoggingLevel.ERROR, 'SEEDED USER ' + u.Id);