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
create or replace view first_touch_attribution as
with journey_ranked as (
select
	user_id,
    source,
    medium,
    campaign_id,
    campaign_name,
    conversion_id,
    revenue,
	row_number() over(partition by user_id order by timestamp ) as touch_order
from user_journey
)
select * from journey_ranked where touch_order = 1;

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
create or replace view last_touch_attribution as
with journey_ranked as (
select
	user_id,
    source,
    medium,
    campaign_id,
    campaign_name,
    conversion_id,
    revenue,
	row_number() over(partition by user_id order by timestamp desc ) as touch_order
from user_journey
)
select * from journey_ranked where touch_order = 1;

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
create or replace view linear_attribution as
select
    user_id,
    source,
    medium,
    campaign_id,
    campaign_name,
    conversion_id,
    revenue,
    count(*) over (
        partition by user_id
    ) as total_touches,
    1.0 / count(*) over (
        partition by user_id
    ) as attribution_weight,
    revenue * (
        1.0 / count(*) over (
            partition by user_id
        )
    ) as attributed_revenue
from user_journey;

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