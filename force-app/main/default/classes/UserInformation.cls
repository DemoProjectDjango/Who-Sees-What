public with sharing class UserInformation {
    @AuraEnabled(cacheable=true)
    public static String getName() {
        String FirstName = UserInfo.getFirstName();
        System.Debug('FirstName-' + FirstName);
        return FirstName;
    }

    @AuraEnabled(cacheable=true)
    public static String getTiming() {
        
        if(System.now().hour()<12){
            return 'Morning';
        }
        else if(System.now().hour() >= 12 && System.now().hour() < 17){
            return 'Afternoon';
        }
        else{
            return 'Evening';
        }
    }

    @AuraEnabled(cacheable=true)
    public static Integer getExpiryDays(){
        try {
            List<organization> objList = [select TrialExpirationDate from organization limit 1];
            Date earliestDate = Date.ValueOf(objList[0].TrialExpirationDate);
            Date latestDate = Date.today();

                Integer daysBetween = latestDate.daysBetween(earliestDate);

            return daysBetween;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}