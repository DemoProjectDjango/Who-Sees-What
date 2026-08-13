public with sharing class DynamicLinkHelper {
  @AuraEnabled(cacheable=true)
  public static DynamicLink__c getDynamicLinkByIdentity(String identifier) {
    return [
      SELECT
        Id,
        Name,
        App_API_Name__c,
        Identity__c,
        Object__c,
        Page_Name__c,
        Relationship_API_Name__c,
        Text_Value__c,
        Where_Condition__c,
        RecordType.DeveloperName,
        Page__c,
        Link__c,
        Relative_Url__c,
        Setup_Page__c,
        Site_Name__c
      FROM DynamicLink__c
      WHERE Identity__c = :identifier
    ];
  }

  @AuraEnabled(cacheable=true)
  public static List<SObject> getObjectIdFromQuery(
    String objectAPIName,
    String whereCondition
  ) {
    //create and execute select id query from objectAPIName and where condition variables
    if (String.isEmpty(objectAPIName)) {
      throw new AuraHandledException(
        'Object API Name cannot be null or empty.'
      );
    }
    if (String.isEmpty(whereCondition)) {
      throw new AuraHandledException(
        'Where Condition cannot be null or empty.'
      );
    }
    try {
      String query =
        'SELECT Id FROM ' +
        objectAPIName +
        ' WHERE ' +
        whereCondition;
      return Database.query(query);
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  @AuraEnabled(cacheable=true)
  public static String getSetupPageLink(String objectAPIName, String record) {
    //create and execute select id query from objectAPIName and where condition variables
    if (String.isEmpty(objectAPIName)) {
      throw new AuraHandledException(
        'Setup page Name cannot be null or empty.' + objectAPIName
      );
    }
    String base_url = System.Url.getOrgDomainUrl().toExternalForm();
    String noRedirect = '?noredirect=1';
    try {
      String whereCondition =
        'Label like \'' +
        '%' +
        objectAPIName +
        '%' +
        '\'';
      String query =
        'SELECT Setup_Page_URL__c FROM Setup_Page_Map__mdt' +
        ' WHERE ' +
        whereCondition;

      List<Setup_Page_Map__mdt> setupPage = Database.query(query);
      if (setupPage.isEmpty()) {
        throw new AuraHandledException(
          'No Setup Page record for ' + objectAPIName
        );
      }
      if (String.isEmpty(setupPage[0].Setup_Page_URL__c)) {
        throw new AuraHandledException(
          'No Setup Page url missing' + objectAPIName
        );
      }
      if (objectAPIName == 'Contact') {
        noRedirect = noRedirect + '&isContactEntityOverride=1';
      }
      String url =
        base_url +
        setupPage[0].Setup_Page_URL__c +
        '/' +
        record +
        noRedirect;
      return url;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  @AuraEnabled(cacheable=true)
  public static String getSiteUrl(String networkId) {
    try {
      String url = Network.getLoginUrl(networkId).substringBefore('.com');
      return url + '.com';
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<SObject> getRecordIdFromDynamicLinkType(
    String dyanmicLinkType,
    String whereCondition
  ) {
    if (String.isEmpty(dyanmicLinkType)) {
      throw new AuraHandledException(
        'DynamicLinkType cannot be null or empty.'
      );
    }
    if (String.isEmpty(whereCondition)) {
      throw new AuraHandledException(
        'Where Condition cannot be null or empty.'
      );
    }
    try {
      String query = '';
      switch on dyanmicLinkType {
        when 'SurveyRecordPage' {
          query =
            'Select Id from SurveyVersion Where SurveyId in (Select Id from Survey Where ' +
            whereCondition +
            ') Order by VersionNumber DESC Limit 1';
        }
        when 'FlowRecordPage' {
          query =
            'SELECT ActiveVersionId FROM FlowDefinitionView WHERE ' +
            whereCondition +
            ' LIMIT 1';
        }
        when 'DPERecordPage' {
          query =
            'SELECT Id FROM BatchCalcJobDefinition WHERE ' +
            whereCondition +
            ' LIMIT 1';
        }
        when 'CommunityPage' {
          query = 'Select Id from Network Where ' + whereCondition + ' LIMIT 1';
        }
      }

      return Database.query(query);
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }
}