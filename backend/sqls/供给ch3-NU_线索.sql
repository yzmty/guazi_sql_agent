/*
file:供给ch3-NU_线索.sql,
指标:瓜子新客数量|T0线索量|T1线索量|T3线索量|T7线索量|T14线索量|T21线索量|T30线索量
业务：C1
场景：漏斗表|供给周报的cohort|包括瓜子新客-线索量
标签：NU|线索量|人数|漏斗|转率|cohort|瓜子新客|瓜子新客数量|T0线索量|T1线索量|T3线索量|T7线索量|T14线索量|T21线索量|T30线索量
维度：日期nu_dt|渠道channel|新渠道(具体渠道)new_channel|投放类型user_type
核心表：dw_user_act_inc_ymd|dw_ctob_tracking_car_owner_behavior_inc_ymd|dim_com_car_clue_ymd|dm_tracking_dau_attribute_state_ymd
作者：宋明瑞|杨悦芳
描述：用于供给周报的瓜子新客数量-线索量的漏斗转化率
*/
--------------------------------------
-- 3.NU-线索
--------------------------------------
-- GZ新客
with gz_nu as (
    select
        dt as nu_dt
        ,guid as gz_guid
		, channel , new_channel ,user_type
    from guazi_dw_dw.dw_user_act_inc_ymd
    where dt between '${start}' AND '${date_y_m_d}'
      and line = 'c2c'
      and is_app = 1
      and is_pageload = 1
      and platform in ('android', 'ios', 'harmony')
      and is_newuser = 1
      and source_ca_s != 'app_aso'
),
-- C1
c1_dau as (
    select  
        guid as c1_guid
        ,dt as c1_dt
    from guazi_dw_dw.dw_ctob_tracking_car_owner_behavior_inc_ymd
    where dt between '${start}' AND '${date_y_m_d}'
      and platform in ('android', 'ios', 'harmony')
      and line = 'c2c'
      and pv > 0 
      and coalesce(ca_s, '') != 'app_aso'
),
c1_nu as ( -- C1新客：关联瓜子新客的条件
select 
c1_dt,
c1_guid
from gz_nu  
join c1_dau on gz_nu.nu_dt=c1_dau.c1_dt and gz_nu.gz_guid= c1_dau.c1_guid
)
,
-- 线索
clue as (
    select 
        guid
        ,clue_id
        ,substr(create_time, 1, 10) as clue_dt
    from guazi_dw_dwd.dim_com_car_clue_ymd
    WHERE dt = '${date_y_m_d}'
      and is_valid = 1
      and is_salvage = 0
      and is_open_city = 1
      and ctob_busi_type_code = 1
      and substr(create_time, 1, 10) between '${start}' AND '${date_y_m_d}'
)
,channel as (
select dt,guid,
nu_user_type  user_type
,nu_channel  channel
,nu_new_channel  new_channel
from guazi_dw_dm.dm_tracking_dau_attribute_state_ymd
where dt between '${start}' and '${date_y_m_d}'
and line = 'c2c'
and platform in ('android', 'ios', 'harmony')
and is_newuser = '新客'
)

select 
    gn.nu_dt
	, nvl(c.channel, '无归因')channel
	, nvl(c.new_channel, '无归因')new_channel
	, nvl(c.user_type , '无归因')user_type
    , count(distinct gn.gz_guid) as nu_cnt, -- 瓜子当日新客
    -- 线索
    count(distinct case when DATEDIFF(cast(c1.clue_dt  as date),cast(gn.nu_dt as date)) = 0 then c1.guid  end) as nu_t0,
	 count(distinct case when DATEDIFF(cast(c1.clue_dt  as date),cast(gn.nu_dt as date)) <= 1 then c1.guid  end) as nu_t1,
    count(distinct case when DATEDIFF(cast(c1.clue_dt  as date),cast(gn.nu_dt as date)) <= 3 then c1.guid  end) as nu_t3,
    count(distinct case when DATEDIFF(cast(c1.clue_dt  as date),cast(gn.nu_dt as date)) <= 7 then c1.guid  end) as nu_t7,
    count(distinct case when DATEDIFF(cast(c1.clue_dt  as date),cast(gn.nu_dt as date)) <= 14 then c1.guid  end) as nu_t14,
    count(distinct case when DATEDIFF(cast(c1.clue_dt  as date),cast(gn.nu_dt as date)) <= 21 then c1.guid  end) as nu_t21,
    count(distinct case when DATEDIFF(cast(c1.clue_dt  as date),cast(gn.nu_dt as date)) <= 30 then c1.guid  end) as nu_t30
from gz_nu gn 
left join clue c1 
on gn.gz_guid = c1.guid 
and gn.nu_dt <= c1.clue_dt 
and DATEDIFF(cast(c1.clue_dt as date),cast(gn.nu_dt as date)) <= 30
left join channel c on gn.gz_guid=c.guid
group by 1 ,2, 3,4