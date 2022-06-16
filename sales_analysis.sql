create table userbehavior(
userID int,
itemID int,
categoryID int,
behaviortype text,
time_stamp int
);

-- Because I only loaded around 800,000 rows data, so I need to check the distribution of each 
-- behavior type to see that all types were loaded
select behaviortype, count(time_stamp) as type_number
from userbehavior 
group by behaviortype;

select count(*) from userbehavior;


-- Data Quality Assement: --

-- Duplicate record checking by using userid, itemid and timestamp as PK
-- There is no duplicate result
select userID, itemID, time_stamp 
from userbehavior
group by userID, itemID, time_stamp 
having count(time_stamp) > 1;

-- Missing value checking
-- The count_value are same, which means there is no missing value.
select count(userID), 
		count(itemID),
        count(categoryID),
		count(behaviortype),
        count(time_stamp)
from userbehavior;


-- The data set are too large, so first to create a test_sample (limit 5000) to conduct the analysis 
-- before applying it to the whole dataset
create table usertest(
    select * from userbehavior limit 5000
    );
select * from usertest limit 10;

-- Timestamp conversion
-- Because later the analysis based on date and time
alter table usertest add datee date,
					add timee varchar(10);
set sql_safe_updates=0; -- to dismiss error when using Update-Set clause without Where 
Update usertest 
set datee=FROM_UNIXTIME(time_stamp,'%Y-%m-%d'),
	timee=FROM_UNIXTIME(time_stamp,'%h'); -- if %k, only show one digit

select * from usertest limit 10;

-- Abnormal value
-- Dataset date range is from 2017-11-25 to 2017-12-03
-- But this sample range is from 2017-09-11 to 2017-12-04, thus need to delete the record outside the range 
select min(datee), max(datee) 
from usertest;

-- There are 187 rows
select count(1) from usertest where datee < '2017-11-25' or datee > '2017-12-03';

delete from usertest where datee < '2017-11-25' or datee > '2017-12-03';

select count(1) from usertest;
-- After data quality assessment, 4813 rows left;


-- User Behavior Analysis: --

-- Number of user behavior in each type:
select behaviortype, count(1) as Num
from usertest 
group by 1;

-- create view: for behavior types, based on each customer on each item 
create view user_P 
as 
select userID, itemID, 
sum(case when behaviortype='pv' then 1 else 0 end) as click,
sum(case when behaviortype='fav' then 1 else 0 end) as favorite, 
sum(case when behaviortype='cart' then 1 else 0 end) as cart,
sum(case when behaviortype='buy' then 1 else 0 end) as buy
from usertest
group by userID, itemID;


-- Understand customer behavior through purchase process 
-- total click: 4395
select sum(click) from user_P;

-- click then buy: 52
select sum(buy) from user_P
where click>0 and buy>0 and favorite=0 and cart=0;

-- click then cart: 109
select sum(cart) from user_P
where click>0 and cart>0;

-- click then cart then buy: 6
select sum(buy) from user_P
where click>0 and cart>0 and buy>0;

-- click then fav: 29
select sum(favorite) from user_P
where click>0 and favorite>0;

-- click then fav then buy: 3
select sum(buy) from user_P
where click>0 and favorite>0 and buy>0;

-- click then fav+cart:null
select sum(cart)+sum(favorite) from user_P
where click>0 and cart>0 and favorite>0;

-- click then fav+cart then buy:null
select sum(cart)+sum(favorite) from user_P
where click>0 and cart>0 and favorite>0 and buy>0;

-- only click without engage with other activities: 3969
select sum(click) from user_P
where click>0 and cart=0 and favorite=0 and buy=0;

-- The result show that:
-- Click-Buy conversion rate is only 1.2%
-- Click-Cart-Buy conversion rate is 5.5%
-- Click-Fav-Buy conversion rate is 4.5%
-- Loss rate is 90.3%

-- 1. Identify the issue:
-- Each process conversion rate is low? Why?

-- 2. Multi-dimensional analysis
-- From Product:
-- 1) The product description did NOT match with adv (Comment Data)
-- 2) The price is too high (Competitor pricing data)
-- 3) Not much option: size, color (Comment Data)

-- From App:
-- 1) The customer interation with the app is not reasonable () 
-- 2) The buying process is NOT convenient (Interaction Data)
-- 3) The recommonded algorithm is NOT precise 

-- For 3) we can assume:  
-- Null hypothesis: What we recommend is customer like and need

-- Top 10 category in viewing:
Select categoryID, count(categoryID) Click 
from usertest
where behaviortype='pv'
group by 1
order by 2 desc limit 10;

-- Top 10 category in buying:
Select categoryID, count(categoryID) Click 
from usertest
where behaviortype='buy'
group by 1
order by 2 desc limit 10;

-- Top 10 item in viewing:
Select itemID, count(itemID) Click 
from usertest
where behaviortype='pv'
group by 1
order by 2 desc limit 10;

-- Top 10 item in buying:
Select itemID, count(itemID) Click 
from usertest
where behaviortype='buy'
group by 1
order by 2 desc limit 10;

-- only one category matching, which mean the highest click 
-- might not bring high conversion rate 


-- Each item conversion rate in Top 10 veiwing category:
select itemID, ifnull(buy,0) as buy  from 
(Select itemID, count(itemID) as buy
from usertest
where behaviortype='buy'
group by 1) t
where itemID in (3471238,
				2492167,
				987677,
				4354614,
				404297,
				1669287,
				106742,
				2452885,
				3930186,
				1793088);

-- Each item clicks in Top 10 buying category:
select * from 
(SELECT itemID,count(itemID) as click
from userbehavior
where BehaviorType = 'pv'
group by 1 ) as t
where itemID in (387031,
				843421,
				2712827,
				1242107,
				3294376,
				167362,
				4753136,
				2971043,
				1606258,
				4840649);

-- Conclusion from this dimension :
-- Reject hypothoesis: Customers did not like the recommended items
-- Top click items have little conversion rate.

-- 3. Provide recommendations: 
-- -- 1) optimise the recommended alrigorithm
-- -- 2) improve the userface interaction
-- -- 3) provide guidance on purchasing process, like connect customer service for coupon

-- RFM Model Analysis 
create view rfm
as
select userID, 
		datediff('2017-12-03', max(datee))+1 as R,
        count(behaviortype) as F
from usertest
where behaviortype ='buy'
group by 1;

-- Find the max and min to set value for F, R
select max(F) as max_f, min(F) as min_f,
		max(R) as max_r, min(R) as min_r
from rfm;

-- Cal each score R and F 
create table RF(
select *, 
		(case when F<=3 then 1
			when F between 4 and 6 then 2
			when F between 7 and 9 then 3
            when F between 10 and 12 then 4
            end) as F_score,
		(case when R between 7 and 9 then 1
				when R between 5 and 6 then 2
                when R between 3 and 4 then 3
                when R between 1 and 2 then 4 
                end) as R_score
from rfm);

-- Cal the average value of R and F 
select avg(R_score), avg(F_score) 
from RF;

-- Compare to avg to define the high/low value customer group
-- Segmentation:
select Cust_segments, count(userID) as total_num
from
(
select userID,
		(case when R_score > 2.9286 and F_score > 1.5000 then 'High RF' 
				when R_score <= 2.9286 and F_score > 1.5000 then 'LowR HighF'
				when R_score > 2.9286 and F_score <= 1.5000 then 'HighR LowF'
				when R_score <= 2.9286 and F_score <= 1.5000 then 'Low RF'
                end) as Cust_segments
from RF
) t
group by 1;

## Low RF --> This group of customers might leave soon, we need to approach them directly (like email
			-- so we need to further inverstigate and find out why
## High RF --> we can provide VIP service for this group 
## HighR LowF --> Figure out how to improve its conversion rate
## LowR HighF --> They were old royal customer, which need to provide them some promotion 
				-- or email to remind them 

-- Final conclusion and suggestion: 
-- 1) Optimise the recommendation system 
-- 2) From Funnel ananysis, we can see the higher interaction, the higher conversion
-- so we need to encourage customer to interact with app.
-- 3) From RFM model, we know that we have a high portion of HighR LowF customer group, consider to provide some rewards to motiviate the purchase




