User u = [SELECT Id FROM User WHERE LastName = 'Einstein' AND IsActive = true ORDER BY CreatedDate DESC LIMIT 1];
insert new Contact(LastName = 'test 02 std', OwnerId = u.Id);
insert new Contact(LastName = 'test - 01 sys');
System.debug(LoggingLevel.ERROR, 'SEEDED CONTACTS FOR ' + u.Id);