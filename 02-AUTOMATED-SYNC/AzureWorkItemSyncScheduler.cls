/**
 * @description Schedulable Apex class to schedule the AzureWorkItemSyncBatch.
 * This class is responsible for initiating the synchronization process periodically.
 * 
 * @author Portfolio Demo - Sanitized Version
 * @note This is a sanitized version removing client-specific references
 */
public class AzureWorkItemSyncScheduler implements Schedulable{

    /**
     * @description The main execution method for the scheduled job.
     * It initiates the AzureWorkItemSyncBatch.
     * @param sc The SchedulableContext.
     */
    public void execute(SchedulableContext sc){
        System.debug(LoggingLevel.INFO, 'AzureWorkItemSyncScheduler triggered. Executing AzureWorkItemSyncBatch.');
        Database.executeBatch(new AzureWorkItemSyncBatch(), 200);
    }

    /**
     * @description A helper method to easily schedule this job from Anonymous Apex or Developer Console.
     * Example: AzureWorkItemSyncScheduler.scheduleJob('DailyAzureSync', '0 0 1 * * ?'); // Daily at 1 AM
     * @param jobName The name to give the scheduled job (must be unique).
     * @param cronExpression The cron expression defining the schedule.
     */
    public static void scheduleJob(String jobName, String cronExpression){
        System.schedule(jobName, cronExpression, new AzureWorkItemSyncScheduler());
        
        System.debug(LoggingLevel.INFO, 'Scheduled job: ' + jobName + ' with cron: ' + cronExpression);
    }
}
