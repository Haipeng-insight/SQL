-- Survival analysis estimates how long it takes for a particular event to happen.
-- A customer starts; when will that customer stop? By assuming that the future will be similar to the past (the homogeneity assumption)

-- The following analysis will be starting with the hazard,
-- Then moving to survival, and then extracting useful measures from the survival probabilities. 
-- The final example is using survival analysis to estimate customer value, or at least estimate future revenue

-- The survival curve is the probability that a customer has not churned yet which always starts at 100% 
-- and decreases teword 0 over time.
-- Survival is the probability that someone survives to a given point in time.
-- The hazard, is the probability that someone succumbs to a risk(like customer churn) at a given point in time.
-- The long-term trend in the hazard probabilities is a good measure of loyalty, 
-- because it shows what happens as customers become more familiar with you.

-- The data is from a fictional mobile phone company that sells mobile phone in three markets.
-- The data is in the form of a transaction log, with one row per transaction.
-- The table used in the analysis is subs, which contains the following columns:
-- customer_id: a unique identifier for each customer
-- start_date: the date the customer started
-- stop_date: the date the customer stopped
-- stop_type: the reason the customer stopped, null or empty if the customer is still active
-- market: the market the customer is in
-- channel: the channel the customer was acquired through
-- monthly_fee: the monthly fee the customer is paying
-- tenure: the number of days the customer has been a customer


use mobile;

-- check the stop_type
-- there are 4 types of stop_type: 1. v-volunteer, 2. I-involunteer, 3. M-migration, 4. null -active
select  stop_type, count(1) as number, min(customer_id) as min_customer_id, 
max(customer_id) as max_customer_id
from subs
group by stop_type;

-- check the tenure value
-- there exists negative tenure which is a potential error and we need to exclude them in the following analysis
select  tenure, count(1) as number, min(customer_id) as min_customer_id
from subs
group by tenure
order by tenure;

-- Figure out the start and stop number of each year
-- There is 0 customer stopped before 2004 which is a potential error. 
-- To fix this, we only use the data after 2004
SELECT YEAR(date) as year,  sum(start) as start, sum(stop) as stop
FROM
(   
SELECT start_date AS date, 1 as start, 0 as stop 
FROM  subs 
UNION ALL
SELECT stop_date AS date, 0 as start, 1 as stop
FROM subs
) as t
GROUP BY year
ORDER BY year;


-- The hazard is the probability that someone succumbs to a risk at a given point in time.
-- here we calculate the hazard probability of customers having tenure as 100 days 
select 100 as tenure, count(*) as popatrisk,
sum(case when stop_type is not null and tenure = 100 then 1 else 0 end) as succumbtorisk,
avg(case when stop_type is not null and tenure = 100 then 1.0 else 0 end)  as h_100
from subs
where start_date >= '2004-01-01' and tenure >=100;
-- 100	2589423	3399	0.00131

-- what proportion of customers who started more than 100 days before '2006-12-28' and survived to at least tenure 100 until?
SELECT 100 as tenure, count(*) as popatrisk,
sum(case when stop_type is not null and tenure < 100 then 1 else 0 end) as succumbtorisk,
avg(case when stop_type is null or tenure >= 100 then 1.0 else 0 end)  as s_100
from subs
where start_date >= '2004-01-01' and tenure >=0
and start_date <= date_sub( '2006-12-28', interval 100 day);

select date_sub( '2006-12-28', interval 100 day);
--100  2897369	307946	0.89372

-- calculate survival probability for all tenures
-- 1. create a table to store survival probability of all tenures. by this way, we can calculate the survival probability and accumulated survival probability step by step
-- 2. load the table with calculated numbers of total customers and who stopped at each tenure
-- 3. calculate the cumulative population till to the tenure t
-- 4. calculate the hazard probability which is the ratio of number of stopped customers and accumulative population
-- 5. calculate the survival probability which is the product of (1-hazard probability) of all previous tenures or 1 if tenure = 0
create table IF NOT EXISTS survival 
( tenure int,
popt int,
stopt int,
cumpopt int,
hazard float,
survival float,
endtenure int,
numberdays int
);

-- load the table with number of population and stopped customer at each tenure
insert into survival
( tenure, popt, stopt, cumpopt, hazard, survival, endtenure, numberdays)
SELECT tenure, count(1) as popt
, sum(case when stop_type is not null and stop_type!='' then 1 else 0 end) as stopt,
null as cumpopt, null as hazard, null as survival, null as endtenure, null as numberdays
from subs
where start_date >= '2004-01-01' AND tenure >=0
group by tenure;

-- update the Endtenure and numberdays
UPDATE survival, 
(
    SELECT s1.tenure
    ,min(case when s1.tenure< s2.tenure then s2.tenure-1 end) as endtenure 
    FROM  survival s1 LEFT JOIN survival s2 on s1.tenure<=s2.tenure
    GROUP BY s1.tenure
    order by s1.tenure
) as subs
SET survival.endtenure = subs.endtenure
, survival.numberdays = subs.endtenure - survival.tenure + 1
WHERE survival.tenure = subs.tenure;
-- update the cumpopt 
UPDATE survival,
(
    SELECT tenure
    , sum(popt) over(order by tenure ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) as cumpopt
    FROM survival
)ssum
SET  survival.cumpopt = ssum.cumpopt
WHERE survival.tenure = ssum.tenure;

-- update the hazard probability
UPDATE survival
SET hazard = (stopt*1.0)/cumpopt
WHERE cumpopt > 0;

-- update the survival probability
-- using the EXP(SUM(LOG(1-s2.hazard))) to calculate the survival probability since the sql does not support product of all previous rows, 
UPDATE survival,
(SELECT s1.tenure, 
case when s1.tenure = 0 then 1 else EXP(SUM(LOG(1-s2.hazard))) end as survival
FROM survival s1 LEFT JOIN survival s2 on s1.tenure >s2.tenure
GROUP BY s1.tenure) as subs
SET survival.survival = subs.survival
WHERE survival.tenure = subs.tenure;

-- fix Endtenure and numberdays for the last row
-- Extending the final survival for a long time to make it possible to look up survival values in the table
update survival
set endtenure = tenure + 100000 -1, numberdays = 100000
where endtenure is null;

-- check the first 10 rows of the survival table
SELECT * FROM survival ORDER BY tenure LIMIT 10;


/*
Comparing different groups of Customers
-- Summarizing the Market
-- Stratifying the Market
-- Survival ratio
-- Conditional survival ratio
*/
-- Summarizing the Market
-- looking at the proportion of of customers in each market who are active as of the cutoff date
-- when comparing the avg-tenure, we also need to think when the company start to break into that market
SELECT market, count(1) as total, avg(tenure) as avg_tenure
, sum(case when stop_type is null or stop_type='' then 1 else 0 end) as active
, avg(case when stop_type is null or stop_type='' then 1.0 else 0 end) as active_rate
FROM subs
WHERE start_date >= '2004-01-01' and tenure >=0
GROUP BY market;

-- Stratifying the Market
-- looking at the proportion of of customers in each market who are active
-- method 1: using the sum(case when ... then 1 else 0 end) to calculate the number of active customers in each market
SELECT tenure
, sum(case when market = 'Gotham'  then 1 else 0 end) as popg
, sum(case when market = 'Metropolis' then 1 else 0 end) as popm
, sum(case when market = 'Smallville' then 1 else 0 end) as pops
, sum(case when market = 'Gotham' and (stop_type is not null and  stop_type !='') then 1 else 0 end) as stopg
, sum(case when market = 'Metropolis' and (stop_type is not null and  stop_type !='') then 1 else 0 end) as stopm
, sum(case when market = 'Smallville' and (stop_type is not null and  stop_type !='') then 1 else 0 end) as stops
FROM subs
WHERE start_date >= '2004-01-01' and tenure >=0
GROUP BY tenure
order by 1;

-- method 2(bettor to avoid ): using the identifier to calculate the number of active customers in each market
SELECT tenure, sum(img) as popg, sum(imm) as popm, sum(ims) as pops
, sum(img * stopt) as stopg
, sum(imm * stopt) as stopm
, sum(ims * stopt)  as stops
FROM
(
SELECT s.*
, case when market = 'Gotham' then 1 else 0 end as img
, case when market = 'Metropolis' then 1 else 0 end as imm
, case when market = 'Smallville' then 1 else 0 end as ims
, case when stop_type is not null and stop_type !='' then 1 else 0 end as stopt
FROM subs s
WHERE start_date >= '2004-01-01' and tenure >=0
) as t
GROUP BY tenure
order by 1;
-- --The left result can found in excel

-- Survival ratio is dividinding the survival probability of one group by the survival probability of another group
-- -- see excel for the visualization
-- -- using the best survival as the standard

-- conditional survival answer the question: given that a customer has survived to a certain point,
-- what is the probability that they will survive to a later point?
-- contract expiration typically occurs after one year, however some customers procastinate, so a period a bit little longer than
-- year is useful, like where tenure>=390
-- fortenure <390, survival probability is 1 for assumption that all customers survive to 390 
-- for tenure >=390, the conditional survival probability is the ratio of survival probability of tenure t divided by survival probability of tenure 390
-- implement the conditional survival probability in excel



/*
Comparing Suvival over time
-- How has a Particular Hazard Changed over Time?
-- What is Customer Survival by Year of a given Start?
-- what did survival look like in the Past?
*/
-- How has a Particular Hazard Changed over Time?
-- since annuaversary churn is a common phenomenon, we can calculate the hazard probability of customers having tenure as 365 days
-- 1. calculate the hazard probability of customers having tenure as 365 days as for 2006-02-15
select 365 as tenure, count(*) as pop365,
sum(case when stop_date='2006-02-15' then 1 else 0 end) as s365,
avg(case when stop_date='2006-02-15' then 1 else 0 end ) as h365
from subs
where (stop_date >='2006-02-15' or stop_date is null )
and start_date = date_sub('2006-02-15', interval 365 day);

-- 2. calculate the hazard probability of customers having tenure as 365 days from 2005-2006
-- the trick is to use the date_add function to calculate the date 365 days after the start date and add it as a indicator
-- all customers who are active after 365 days after they start are in the population of at risk on exactly that day
-- of those, some customers stop, as captured by the stop date being 365 days after the start date(date365)
SELECT date365, count(*) as pop365,
sum(case when stop_date=date365 and (stop_type is not null or stop_type!='')  then 1 else 0 end) as s365
, avg(case when stop_date=date365 and (stop_type is not null or stop_type!='')  then 1 else 0 end) as h365
from (select *, date_add(start_date, interval 365 day) as date365 from subs) s
where start_date >= '2004-01-01' and tenure >=365
group by date365
order by date365;

-- What is Customer Survival by Year of a given Start?
SELECT tenure, sum(y2004) as p2004, sum(y2005) as p2005, sum(y2006) as p2006
,sum(y2004*stopt) as s2004, sum(y2005*stopt) as s2005, sum(y2006*stopt) as s2006
FROM
(
SELECT *,
CASE WHEN YEAR(start_date) = 2004 THEN 1 ELSE 0 END as y2004,
CASE WHEN YEAR(start_date) = 2005 THEN 1 ELSE 0 END as y2005,
CASE WHEN YEAR(start_date) = 2006 THEN 1 ELSE 0 END as y2006,
CASE WHEN stop_type IS NOT NULL AND stop_type!='' THEN 1 ELSE 0 END as stopt
FROM mobile.subs 
WHERE start_date >= '2004-01-01' and tenure >=0) s
GROUP BY tenure
order by 1;
;

-- what did survival look like in the Past? such as 2004-12-31
-- 1. only the customers that were enrolled and active before 2004-12-31 were included in the population
-- 2. remark the stop_type, if the stop_type is null, then the customer is still active
-- 3. calculate the tenure as for the cutoff date
-- 3. calculate the survival probability of 2004-12-31


USE mobile;
SELECT tenure_cutoff, count(1) as popt,
sum(stop_cutoff ) as stopt
FROM
(
SELECT *,
CASE WHEN stop_type is not null and stop_type!='' and stop_date < cutoff THEN tenure
     ELSE datediff(cutoff, start_date) END as tenure_cutoff,
CASE WHEN stop_type is null or stop_type='' THEN 0
     WHEN stop_type is not null and stop_type!='' and stop_date > cutoff THEN 0
     ELSE 1 END as stop_cutoff
From 
(
SELECT *, cast('2004-12-31'as date) as cutoff from mobile.subs
) as s
WHERE start_date >= '2004-01-01' AND start_date <=cutoff and tenure >=0
) as t
GROUP BY tenure_cutoff
order by 1;


-- Here are the query that calculate the survival of the end of 2004,2005 and 2006
use mobile;
SELECT tenure, sum(p2004) as p2004, sum(p2005) as p2005, sum(p2006) as p2006
,sum(s2004) as s2004, sum(s2005) as s2005, sum(s2006) as s2006
FROM
(
    SELECT newtenure as tenure
    , count(1) as p2004, 0 as p2005, 0 as p2006
    , sum(thestop) as s2004, 0 as s2005, 0 as s2006
    FROM
    (
    SELECT *,
        CASE WHEN stop_type != '' AND stop_type IS NOT NULL AND stop_date < cutoff THEN tenure ELSE datediff(cutoff, start_date) END as newtenure,
        CASE WHEN stop_type != '' AND stop_type IS NOT NULL AND stop_date > cutoff THEN 0 
            WHEN stop_type is null or stop_type='' then 0 ELSE 1 END as thestop
    FROM
    (SELECT *, CAST('2004-12-31' as date) as cutoff from mobile.subs)  s
    WHERE start_date >= '2004-01-01' AND start_date <= cutoff and tenure >=0
    ) t
    GROUP BY newtenure
UNION ALL
        SELECT newtenure as tenure
    , 0 as p2004, count(1) as p2005, 0 as p2006
    , 0 as s2004, sum(thestop) as s2005, 0 as s2006
    FROM
    (
    SELECT *,
        CASE WHEN stop_type != '' AND stop_type IS NOT NULL AND stop_date < cutoff THEN tenure ELSE datediff(cutoff, start_date) END as newtenure,
        CASE WHEN stop_type != '' AND stop_type IS NOT NULL AND stop_date > cutoff THEN 0 
            WHEN stop_type is null or stop_type='' then 0 ELSE 1 END as thestop
    FROM
    (SELECT *, CAST('2005-12-31' as date) as cutoff from mobile.subs)  s
    WHERE start_date >= '2004-01-01' AND start_date <= cutoff and tenure >=0
    ) t
    GROUP BY newtenure
UNION ALL
    SELECT newtenure as tenure
    , 0 as p2004, 0 as p2005, count(1) as p2006
    , 0 as s2004, 0 as s2005, sum(thestop) as s2006
    FROM
        (
    SELECT *,
        CASE WHEN stop_type != '' AND stop_type IS NOT NULL AND stop_date < cutoff THEN tenure ELSE datediff(cutoff, start_date) END as newtenure,
        CASE WHEN stop_type != '' AND stop_type IS NOT NULL AND stop_date > cutoff THEN 0 
            WHEN stop_type is null or stop_type='' then 0 ELSE 1 END as thestop
    FROM
    (SELECT *, CAST('2006-12-31' as date) as cutoff from mobile.subs)  s
    WHERE start_date >= '2004-01-01' AND start_date <= cutoff and tenure >=0
    ) t
    GROUP BY newtenure
) as f
GROUP BY tenure
ORDER BY 1;

/*
Important Measures from Survival
-- Point Estimate of Survival
-- Median Customer Tenure
-- Average Customer Lifetime
-- Confidence in the hazards
*/
-- Point Estimate of Survival
-- -- how many customers are still active to a given point in time
-- --useful for calculating the expected revenue from a customer to identify the aquistion cost
-- --the time could be the end of initial promo period, the end of the first year or any important miltstone in the customer lifecycle

-- Median Customer Tenure
-- -- the median customer tenure is the point at which half of the customers have stopped

-- Average Customer Lifetime
-- -- average truncated tenure: average tenure for a given period or time after the start date, 
-- -- like what is the average number of days that customers are expected to survive in the 1st year after they start  
-- -- the average customer lifetime is the average tenure of all customers who have stopped

-- Confidence in the hazards
-- -- select out the customers who have stopped in one/two/three years after they start
use mobile;
SELECT tenure,
SUM(CASE WHEN start_date>='2006-01-01' THEN 1 ELSE 0 END) as oneyear,
SUM(CASE WHEN start_date>='2005-01-01' THEN 1 ELSE 0 END) as twoyear,
SUM(CASE WHEN start_date>='2004-01-01' THEN 1 ELSE 0 END) as threeyear,
SUM(CASE WHEN start_date>='2006-01-01' and stopt  THEN 1 ELSE 0 END) as oneyearstop,
SUM(CASE WHEN start_date>='2005-01-01' and stopt  THEN 1 ELSE 0 END) as twoyearstop,
SUM(CASE WHEN start_date>='2004-01-01' and stopt  THEN 1 ELSE 0 END) as threeyearstop
FROM
(
SELECT *, case when stop_type is not null and stop_type !='' then 1 else 0 end as stopt 
FROM subs
WHERE start_date >= '2004-01-01' and tenure >=0
) as t
GROUP BY tenure
ORDER BY tenure;
-- -- the SE for 1million customers is small while big for 1000 customers
/*
Using Survival to Estimate Customer Value
-- Estimated Revenue
-- Estimated Future Revenue for one Future start
-- Estimated Revenue for a single group of existing customers
-- Estimated Future Revenue for all customers
*/
-- Estimated Revenue
-- a steam of money that arrives at a given rate, such as $50 per month
-- --using intial monthly fee as a example of estimated revenue
-- -- Actural billing data or payment data would be preferable
-- --Averagea monthly fee of reent starts by marketn and channel should be used as revenue for the prospective customers.
-- --The average monthly fee of existing customers by market and channel 
SELECT market, channel, COUNT(1) AS total_customers
, avg(monthly_fee) as monthly_fee
, avg(monthly_fee)/30.4 as daily_fee
FROM mobile.subs
WHERE start_date >= '2006-01-01' and tenure >=0
GROUP BY market, channel
ORDER BY market, channel;

-- --create revenue table to store the estimated revenue
create table  mobile.revenue AS
 SELECT market, channel
, avg(monthly_fee)/30.4 as daily_fee
FROM mobile.subs
WHERE start_date >= '2006-01-01' and tenure >=0
GROUP BY market, channel
ORDER BY market, channel;

ALTER TABLE mobile.revenue RENAME COLUMN daily_fee to daily_revenue;

select * from mobile.revenue;

-- Estimated Future Revenue for one Future start
-- -- create a table survivalmc which contains market, channel, tenure in days, survival
-- -- the assistance columns are popt, stopt, cumpopt, hazard, endtenure, numberdays
-- -- the endtenure is the last tenure value of the customer in the group in the case of there are missing tenure values
-- -- the numberdays is the number of days between the endtenure and tenure. which can fix the missing tenure values and boundary-effect problems
( market varchar(20),
channel varchar(20),
tenure int,
popt int,
stopt int,
cumpopt int,
hazard float,
survival float,
endtenure int,
numberdays int
);

INSERT INTO mobile.survivalmc
SELECT market, channel, tenure, count(1) as popt, 
sum(case when stop_type is not null and stop_type!='' then 1 else 0 end) stopt,
NULL as cumpopt, NULL as hazard, NULL as survival, NULL as endtenure, NULL as numberdays
FROM mobile.subs
WHERE start_date >= '2004-01-01' and tenure >=0
GROUP BY market, channel, tenure
ORDER BY market, channel, tenure;

-- update the Endtenure and numberdays
UPDATE mobile.survivalmc, 
(
    SELECT s1.market, s1.channel, s1.tenure
    ,min(case when s1.tenure< s2.tenure then s2.tenure-1 end) as endtenure 
    FROM  mobile.survivalmc s1 LEFT JOIN mobile.survivalmc s2 on s1.tenure<=s2.tenure
    GROUP BY s1.market, s1.channel, s1.tenure
    order by s1.market, s1.channel, s1.tenure
) as subs
SET mobile.survivalmc.endtenure = subs.endtenure
WHERE mobile.survivalmc.market = subs.market
AND mobile.survivalmc.channel = subs.channel
AND mobile.survivalmc.tenure = subs.tenure;

UPDATE mobile.survivalmc
SET numberdays = endtenure - tenure + 1
WHERE numberdays is null;

-- update the cumpopt
update mobile.survivalmc,
(
    SELECT market, channel, tenure
    , sum(popt) over(partition by market, channel order by tenure ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) as cumpopt
    FROM mobile.survivalmc
) ssum
SET mobile.survivalmc.cumpopt = ssum.cumpopt
WHERE mobile.survivalmc.market = ssum.market
AND mobile.survivalmc.channel = ssum.channel
AND mobile.survivalmc.tenure = ssum.tenure;

-- update the hazard probability
UPDATE mobile.survivalmc
SET hazard = (stopt*1.0)/cumpopt
WHERE cumpopt > 0;

-- update the survival probability
-- using the EXP(SUM(LOG(1-s2.hazard))) to calculate the survival probability since the sql does not support product of all previous rows,
UPDATE mobile.survivalmc,
(
SELECT s1.market, s1.channel, s1.tenure,
case when s1.tenure = 0 then 1 else EXP(SUM(LOG(1-s2.hazard))) end as survival
FROM mobile.survivalmc s1 LEFT JOIN mobile.survivalmc s2 
on s1.market= s2.market and s1.channel =s2.channel and s1.tenure >s2.tenure
GROUP BY s1.market, s1.channel, s1.tenure) as subs
SET mobile.survivalmc.survival = subs.survival
WHERE mobile.survivalmc.market = subs.market
AND mobile.survivalmc.channel = subs.channel
AND mobile.survivalmc.tenure = subs.tenure;



SELECT * FROM mobile.survivaLmc
 LIMIT 10;

-- Estimated Revenue for the first 365 after a customer start
-- -- the revenue is the product of daily revenue and survival probability AND Number of days(Default is 1)
-- These one-year revenue estimates can be compared to the cost of aquisition to dertermine how much an additional $1000 spent on marketing would be worth
SELECT t.market, t.channel
, sum(daily_revenue * survival * numberday365) as revenue
FROM 
( SELECT s.*
, CASE WHEN endtenure >=365 THEN 365-tenure ELSE numberdays END as numberday365
FROM mobile.survivalmc s ) as t LEFT JOIN mobile.revenue r
ON t.market = r.market AND t.channel = r.channel
WHERE tenure <365
GROUP BY t.market, t.channel
ORDER BY t.market, t.channel;

-- since daily avenue is a conastant, there is a more efficient way to calculate the revenue for the first 365 days
SELECT ssum.market, ssum.channel, survdays * daily_revenue as revenue
FROM 
    (SELECT market, channel
    , sum(survival * numberday365) as survdays
    FROM
    (
    SELECT s.*
    -- fix the year end boundary effect problem
    , CASE WHEN endtenure >=365 THEN 365-tenure ELSE numberdays END as numberday365
    FROM mobile.survivalmc s
    ) as t 
    WHERE tenure <365
    GROUP BY market, channel) as ssum
LEFT JOIN mobile.revenue r
ON ssum.market = r.market AND ssum.channel = r.channel
ORDER BY ssum.market, ssum.channel;

-- Estimated Revenue for a single group of existing customers
-- -- Using the conditional survival probability to calculate the revenue for the existing customers
-- -- Estimated second year revenue for a homogeous group

SELECT s.survival/s365.survival as survival365, s.*
FROM mobile.survivalmc s
LEFT JOIN 
-- define the customer group who have survived to 365 days
(
SELECT market, channel, survival
 FROM mobile.survivaLmc
 -- define the 365 days
 WHERE 365 between tenure and endtenure
 ) s365
ON s.market = s365.market AND s.channel = s365.channel
WHERE s.tenure >= 365; 


-- method : fill out all available tenure values and pridicate the 2nd year revenue through the sum of numberdays and survival probability/survival365
SELECT ssum.market, ssum.channel,numsubs,numactive
, numsubs*survdays*daily_revenue as revenue_start
, numactive*survdays*daily_revenue as revenue_active
FROM
(SELECT market, channel
, count(1) as numsubs
, sum(case when (stop_type is null or stop_type='') and tenure=365
 then 1 else 0 end) as numactive
FROM mobile.subs
WHERE start_date= '2005-12-28' 
GROUP BY market, channel) oneyear 
LEFT JOIN 
(
SELECT t.market, t.channel
, SUM(numberday730*t.survival/s365.survival) as survdays
FROM
(
SELECT market, channel, survival, tenure, 
        (CASE WHEN endtenure >=730 THEN 730-tenure ELSE numberdays END) as numberday730
FROM mobile.survivalmc
) as t
LEFT JOIN 
(
SELECT market, channel, survival
 FROM mobile.survivaLmc
 -- define the 365 days
 WHERE 365 between tenure and endtenure
 ) s365
ON t.market = s365.market AND t.channel = s365.channel
WHERE t.tenure between 365 and  730
GROUP BY t.market, t.channel
) ssum
ON oneyear.market = ssum.market AND oneyear.channel = ssum.channel
LEFT JOIN mobile.revenue r
ON ssum.market = r.market AND ssum.channel = r.channel
ORDER BY ssum.market, ssum.channel;

-- Estimated Future Revenue for all customers
SELECT subs.market, subs.channel, sum(subs.numsubs) as numsubs
, sum(subs.numactive) as numactive
, sum(subs.numactive*sumsurvival1year*daily_revenue) as revenue
, sum(subs.numactive*sumsurvival1year*daily_revenue)/sum(subs.numsubs) as revenue_per_start
, sum(subs.numactive*sumsurvival1year*daily_revenue)/sum(subs.numactive) as revenue_per_activen
FROM
(SELECT market, channel, tenure
, count(1) as numsubs
, sum(case when (stop_type is null or stop_type='')  then 1 else 0 end) as numactive
FROM mobile.subs
WHERE start_date >= '2004-01-01' and tenure >=0
Group BY market,channel, tenure) subs
LEFT JOIN 
(
SELECT s.market, s.channel,  s.tenure, s.numberdays,
sum((slyear.survival/s.survival)*
    (CASE WHEN slyear.endtenure - s.tenure >=365 
    THEN 365-(slyear.tenure-s.tenure) ELSE slyear.numberdays END) 
) as sumsurvival1year
FROM mobile.survivalmc s
LEFT JOIN mobile.survivalmc slyear
ON s.market = slyear.market AND s.channel = slyear.channel
AND slyear.tenure between s.tenure and s.tenure + 365
group by s.market, s.channel, s.tenure, s.numberdays

) as ssum
ON subs.market = ssum.market AND subs.channel = ssum.channel and subs.tenure = ssum.tenure
left join mobile.revenue r
ON subs.market = r.market AND subs.channel = r.channel
GROUP BY subs.market, subs.channel;


