Account a = new Account(Name = 'WSW Probe Account');
insert a;
Contact c = [SELECT Id FROM Contact WHERE LastName = 'test - 01 sys' LIMIT 1];
c.AccountId = a.Id;
update c;
System.debug(LoggingLevel.ERROR, 'LINKED ' + c.Id + ' TO ' + a.Id);