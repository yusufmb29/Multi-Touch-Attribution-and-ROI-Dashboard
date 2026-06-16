select * from ad_spend;
select * from conversions;
select * from user_touchpoints;
select count(distinct user_id) from conversions;
select count(distinct user_id) from user_touchpoints;
select count(distinct campaign_id) from ad_spend;
select count(distinct campaign_id) from user_touchpoints;

-- Creating User Journey Table/View
create or replace view user_journey as
select
    t.user_id,
    t.session_id,
    t.timestamp,
    t.source,
    t.medium,
    t.campaign_id,
    t.campaign_name,
    t.event_type,
    c.conversion_id,
    c.conversion_timestamp,
    c.revenue
from user_touchpoints t
join conversions c
    on t.user_id = c.user_id
where t.timestamp <= c.conversion_timestamp;

select * from user_journey;

select 
	user_id,
	source,
	timestamp,
	row_number() over(partition by user_id order by timestamp ) as touch_order
from user_journey
order by user_id, timestamp
limit 30;
	
select 
	user_id,
	source,
	timestamp,
	row_number() over(partition by user_id order by timestamp ) as touch_order,
	count(*) over(partition by user_id) as total_touches
from user_journey
order by user_id, timestamp
limit 30;

-- First-Touch Attribution Model
-- Asks "Who introduced the customer?"
CREATE OR REPLACE VIEW first_touch_attribution AS
WITH journey_ranked AS (
SELECT
    user_id,
    source,
    medium,
    campaign_id,
    campaign_name,
    conversion_id,
    conversion_timestamp,
    revenue,
    ROW_NUMBER() OVER(
        PARTITION BY user_id
        ORDER BY timestamp
    ) AS touch_order
FROM user_journey
)
SELECT *
FROM journey_ranked
WHERE touch_order = 1;

select * from first_touch_attribution;
select count(*) from first_touch_attribution;

select 
	source, 
	count(*) as conversions, 
	sum(revenue) as attributed_revenue
from first_touch_attribution
group by source
order by attributed_revenue asc;
-- Google is the strongest customer acquisition channel.

-- Last-Touch Attribution Model
-- Asks "Who closed the sale?"
CREATE OR REPLACE VIEW last_touch_attribution AS
WITH journey_ranked AS (
SELECT
    user_id,
    source,
    medium,
    campaign_id,
    campaign_name,
    conversion_id,
    conversion_timestamp,
    revenue,
    ROW_NUMBER() OVER(
        PARTITION BY user_id
        ORDER BY timestamp DESC
    ) AS touch_order
FROM user_journey
)
SELECT *
FROM journey_ranked
WHERE touch_order = 1;

select * from last_touch_attribution;
select count(*) from last_touch_attribution;

select 
	source, 
	count(*) as conversions, 
	sum(revenue) as attributed_revenue
from last_touch_attribution
group by source
order by attributed_revenue asc;
-- Google is best in both customer aquisition and conversion.
-- Facebook and email are better at introducing customers than closing customers.

-- Linear Attribution Model
CREATE OR REPLACE VIEW linear_attribution AS
SELECT
    user_id,
    source,
    medium,
    campaign_id,
    campaign_name,
    conversion_id,
    conversion_timestamp,
    revenue,

    COUNT(*) OVER(PARTITION BY user_id) AS total_touches,

    1.0 / COUNT(*) OVER(PARTITION BY user_id) AS attribution_weight,

    revenue * (
        1.0 / COUNT(*) OVER(PARTITION BY user_id)
    ) AS attributed_revenue

FROM user_journey;

select *
from linear_attribution
limit 15;

select
	source,
	count(*) as attributed_touchpoints,
	round(sum(attributed_revenue),2) as attributed_revenue
from linear_attribution
group by source
order by attributed_revenue desc;

-- Linear Attribution by Campaign
create or replace view linear_campaign_revenue as
select
	campaign_id,
	campaign_name,
	round(sum(attributed_revenue),2) as attributed_revenue,
	count(distinct conversion_id) as attributed_conversions
from linear_attribution
where campaign_id is not null
group by campaign_id, campaign_name;
	
select * from linear_campaign_revenue
order by attributed_revenue desc limit 10;

-- Spend by Campaign View
create or replace view campaign_spend as
select
	campaign_id,
	campaign_name,
	sum(spend) as total_spend,
	sum(clicks) as total_clicks,
	sum(impressions) as total_impressions
from ad_spend
group by
	campaign_id,
	campaign_name;

select * from campaign_spend order by total_spend desc;

-- Create Campaign Performance View
create or replace view campaign_performance as
select
	s.campaign_id,
	s.campaign_name,
	s.total_spend,
	s.total_clicks,
	s.total_impressions,
	coalesce(r.attributed_revenue,0) as attributed_revenue,
	coalesce(r.attributed_conversions,0) as attributed_conversions
from
	campaign_spend s
left join linear_campaign_revenue r
	on s.campaign_id = r.campaign_id;

select * from campaign_performance;

-- Create Campaign KPIs 
create or replace view campaign_kpis as
select *,
	round(attributed_revenue/nullif(total_spend,0),2) as roas
from campaign_performance;

select
    campaign_name,
    total_spend,
    attributed_revenue,
    attributed_conversions,
    roas
from campaign_kpis
order by roas desc
limit 10;

create or replace view campaign_kpis_2 as
select *,
	round(attributed_revenue/nullif(total_spend,0),2) as roas,
	round(total_spend/nullif(attributed_conversions,0),2) as cac
from campaign_performance;

select
    campaign_name,
    total_spend,
    attributed_revenue,
    attributed_conversions,
    roas,
	cac
from campaign_kpis_2
order by cac desc
limit 10;


-- Star Scheme ( Data Modelling )

-- Dim Campaign table
create or replace view dim_campaign as
select distinct
    campaign_id,
    campaign_name,
    platform,
    channel
from ad_spend;

select count(*) from dim_campaign;

-- Dim Date Table
DROP VIEW IF EXISTS dim_date;

CREATE VIEW dim_date AS
SELECT DISTINCT
    date,
    EXTRACT(YEAR FROM date) AS year,
    EXTRACT(MONTH FROM date) AS month_no,
    TO_CHAR(date,'Month') AS month_name,
    TO_CHAR(date,'Mon') AS month_short,
    EXTRACT(QUARTER FROM date) AS quarter,
    EXTRACT(DAY FROM date) AS day,
    TO_CHAR(date,'Day') AS weekday_name,
    EXTRACT(DOW FROM date) AS weekday_no
FROM fact_attribution
ORDER BY date;

select count(*) from dim_date;

-- Fact Attribution Tables
CREATE OR REPLACE VIEW fact_attribution AS

-- First Touch
SELECT
    campaign_id,
    campaign_name,
    conversion_timestamp::date AS date,
    'First Touch' AS model_type,
    SUM(revenue) AS attributed_revenue,
    COUNT(*) AS attributed_conversions
FROM first_touch_attribution
GROUP BY
    campaign_id,
    campaign_name,
    conversion_timestamp::date

UNION ALL

-- Last Touch
SELECT
    campaign_id,
    campaign_name,
    conversion_timestamp::date AS date,
    'Last Touch' AS model_type,
    SUM(revenue) AS attributed_revenue,
    COUNT(*) AS attributed_conversions
FROM last_touch_attribution
GROUP BY
    campaign_id,
    campaign_name,
    conversion_timestamp::date

UNION ALL

-- Linear
SELECT
    campaign_id,
    campaign_name,
    conversion_timestamp::date AS date,
    'Linear' AS model_type,
    SUM(attributed_revenue) AS attributed_revenue,
    COUNT(DISTINCT conversion_id) AS attributed_conversions
FROM linear_attribution
GROUP BY
    campaign_id,
    campaign_name,
    conversion_timestamp::date;

select * from fact_attribution;

SELECT * FROM fact_attribution LIMIT 5;
