/*
file:供给-检测.sql
指标:线索量|检测工单量|上架量|标准上架量|净已定量|总检测时长|检测时长|等待时长|跑动时长|审核时长|审核_上架时长|枉跑时长|单独开上架时长
业务：C1
场景：截面表|供给周报的检测成本时长
标签：|供给|成本|检测成本|检测|检测时长|供给周报|线索量|检测工单量|上架量|标准上架量|净已定量|总检测时长|检测时长|等待时长|跑动时长|审核时长|审核_上架时长|枉跑时长|单独开上架时长
维度：dt|channel_level|投放类型toufang_type|圈车类型|首上架渠道
核心表：dwd_ctob_evaluate_sub_task_ymd|dim_mkt_channel_listing_std_coef|dw_ctob_c1_car_source_ymd|dm_ctob_clue_detail_transform_csd_inc_ymd|dw_ctob_c1_tob_toc_appoint_detail_ymd|dwd_ctob_evaluate_sub_task_ymd|dwd_ctob_car_owner_clue_transform_ymd|dim_mkt_channel_listing_std_coef
作者：宋明瑞|杨悦芳
描述：用于供给周报的检测时长
*/
-- 时长明细
with evaluate_time as (
SELECT 
substr(distribute_time,1,10) dt,
sub_task_id,
clue_id,
start_evaluate_time,
distribute_evaluator,
unix_timestamp(submit_report_time)-unix_timestamp(start_evaluate_time) as check_time_cnt, -- 检测时长
unix_timestamp(start_evaluate_time)-unix_timestamp(arrive_time) as wait_time_cnt,-- 等待时长
running_time*60 as running_time,-- 跑动时长（跑动算法时长）
case when start_evaluate_time is null then running_time*60 else null end as no_value_run_cnt, -- 枉跑时长
unix_timestamp(onshelve_audit_time)-unix_timestamp(submit_report_time) as verify_time_cnt,  -- - 审核时长
unix_timestamp(onshelve_success_time)-unix_timestamp(onshelve_audit_time) as audit_to_onshlve -- - 审核-上架
FROM guazi_dw_dwd.dwd_ctob_evaluate_sub_task_ymd
WHERE dt = '${date_y_m_d}' 
and substr(distribute_time,1,10) between '${start}' and '${end_date}'
and ctob_busi_type_code = 1
),
-- 单独提取每个一级分类下 end_date 最大的一条记录，专门用于超期兜底匹配
coef_max AS (
    SELECT 
        first_level_category, 
        single_listing_revenue_coef, 
        end_date AS max_end_date
    FROM (
        SELECT 
            first_level_category,
            single_listing_revenue_coef,
            end_date,
            ROW_NUMBER() OVER(PARTITION BY first_level_category ORDER BY end_date DESC) as rn
        FROM guazi_dw_import.dim_mkt_channel_listing_std_coef
    ) tmp
    WHERE rn = 1
)
,
-- 作为维度表
clue_info as 
(SELECT distinct 
	ca_s, ca_n ,
    clue_id,
	channel_level1,channel_level2,toufang_type,
	case when channel_level2 = '非主端' then '非主端-端产品'
	when channel_level1 = '非端产品' then '表单'
	when channel_level1 = '商务拓展' then '商务'
	when channel_level1 = '端产品' then '主端'
	else channel_level1 end as channel_level ,
	channel_type_name,
	customer_type_name,
	channel_name ,
	case 
		when  channel_level2 = '主端' and toufang_type = '非投放' and customer_type_name = 'App' then '主端-非投放-APP'
		when  channel_level2 = '主端' and toufang_type = '投放' and customer_type_name = 'App' then '主端-投放-APP'
		when  channel_level2 = '主端' and toufang_type = '非投放' and customer_type_name = '小程序' then '主端-非投放-小程序'
		when  channel_level2 = '主端' and toufang_type = '投放' and customer_type_name = '小程序' then '主端-投放-小程序'
		when  channel_level2 = '非主端' and toufang_type = '非投放' and customer_type_name = 'App' then '非主端-非投放-APP'
		when  channel_level2 = '非主端' and toufang_type = '非投放' and customer_type_name = '小程序' then '非主端-非投放-小程序'
		when  channel_level2 = '非主端' and toufang_type = '投放' and customer_type_name = 'App' then '非主端-投放-APP'
		when  channel_level2 = '非主端' and toufang_type = '投放' and customer_type_name = '小程序' then '非主端-投放-小程序'
		when  channel_level1 = '非端产品' then '非端产品'
		when  channel_level1 = '商务拓展' then '商务拓展'
		when  channel_level1 = '直播' then '直播'
		when  channel_type_name = '网销自建' then '网销自建'
	else '其他' end as new_type
FROM guazi_dw_dw.dw_ctob_c1_car_source_ymd -- C1线索
WHERE dt = '${date_y_m_d}' 
AND is_c1_clue = 1 -- C1车源
)
,
-- 线索量 工单量 上架量
clue_task_onshelf as (
select *
FROM guazi_dw_dm.dm_ctob_clue_detail_transform_csd_inc_ymd         
WHERE dt BETWEEN '${start}' AND '${end_date}' 
and ctob_busi_type_code = 1
),

evaluate_time_2 as (
select a.*,b.toufang_type,b.channel_level1,b.channel_level2,b.channel_level
from evaluate_time a 
left join clue_info b on a.clue_id = b.clue_id
)
-- 净已定
,quantity_set as 
-- 已定表
 (select 
	prepay_time
	, clue_id
	, sum(case when type='set' then 1 else 0 end) 
    - sum(case when type='set_r' then 1 else 0 end) as quantity_set
	from 
	 (
		 select -- 已定
			substr(prepay_time,1,10) as prepay_time
			,clue_id
			,'set' as type
		from guazi_dw_dw.dw_ctob_c1_tob_toc_appoint_detail_ymd
		where dt ='${date_y_m_d}'
		  and ctob_busi_type_code in(1,9,10)
		and ctob_deal_busi_code not in (4,7,9) -- 剔除第一台车
		and substr(prepay_time,1,10) between '${start}' AND '${date_y_m_d}'
		  group by 1,2,3

		union ALL

		 select -- 已定后退
			substr(refund_time,1,10) as refund_time  
			,clue_id
			,'set_r' as type
		from guazi_dw_dw.dw_ctob_c1_tob_toc_appoint_detail_ymd
		where dt ='${date_y_m_d}'
		  and ctob_busi_type_code in(1,9,10)
		and ctob_deal_busi_code not in (4,7,9) -- 剔除第一台车
		and substr(refund_time,1,10) between '${start}' AND '${date_y_m_d}'
		  group by 1,2,3
	)t1
group by 1,2
 ) 
,
-- 这里使用这个C1线索表是为了取得自营C和自营B的平台视角售出的全部clue_id，
-- 以COALESCE(clue_id_self,clue_id) as clue_id和净已定关联，所有的clue_id都可以匹配到对应的市场渠道
clue as 
-- clueid表
(SELECT distinct 
    dt,
    COALESCE(clue_id_self,clue_id) as clue_id,
	channel_level1,channel_level2,toufang_type,
	case when channel_level2 = '非主端' then '非主端-端产品'
	when channel_level1 = '非端产品' then '表单'
	when channel_level1 = '商务拓展' then '商务'
	when channel_level1 = '端产品' then '主端'
	else channel_level1 end as channel_level
FROM guazi_dw_dw.dw_ctob_c1_car_source_ymd -- C1线索
WHERE dt = '${date_y_m_d}'
AND is_c1_clue = 1 -- C1车源
)
,
quantity_set_clue as (
select 
q.clue_id
,quantity_set
,prepay_time
,dt
,toufang_type
,channel_level1
,channel_level2
,channel_level
from quantity_set q
left join clue c on c.clue_id = q.clue_id
)
-- 线索量 工单量 上架量等，和维度表关联
,
c1_channel as (
select a.dt,b.channel_level,b.toufang_type  , cb_sale_type ,new_type ,
a.is_salvage, a.is_75_city , sum(clue_num)clue_num ,
sum(evaluate_num )evaluate_num,
sum(onshelf_num)onshelf_num 
from clue_task_onshelf a
left join clue_info b on a.clue_id = b.clue_id
group by 1,2,3,4 ,5 ,6 ,7
)
, onshelf_time as -- 单独看上架车源的时长
(
select dt,channel_level,toufang_type,
(sum(check_time_cnt)+sum(wait_time_cnt)+sum(running_time)+sum(verify_time_cnt)+sum(audit_to_onshlve))/3600 as onshelf_time_all
from
(
SELECT 
substr(distribute_time,1,10) dt,
sub_task_id,
clue_id,
start_evaluate_time,
distribute_evaluator,
unix_timestamp(submit_report_time)-unix_timestamp(start_evaluate_time) as check_time_cnt, -- 检测时长
unix_timestamp(start_evaluate_time)-unix_timestamp(arrive_time) as wait_time_cnt,-- 等待时长
running_time*60 as running_time,-- 跑动时长（跑动算法时长）
case when start_evaluate_time is null then running_time*60 else null end as no_value_run_cnt, -- 枉跑时长
unix_timestamp(onshelve_audit_time)-unix_timestamp(submit_report_time) as verify_time_cnt,  -- - 审核时长
unix_timestamp(onshelve_success_time)-unix_timestamp(onshelve_audit_time) as audit_to_onshlve -- - 审核-上架
FROM guazi_dw_dwd.dwd_ctob_evaluate_sub_task_ymd 
WHERE dt = '${date_y_m_d}' 
and substr(distribute_time,1,10) between '${start}' and '${end_date}'
and ctob_busi_type_code = 1
) t1 -- 时长
left join
(
select clue_id,channel_level1,channel_level2,toufang_type,
case when channel_level2 = '非主端' then '非主端-端产品'
when channel_level1 = '非端产品' then '表单'
when channel_level1 = '商务拓展' then '商务'
when channel_level1 = '端产品' then '主端'
else channel_level1 end as channel_level
from guazi_dw_dwd.dwd_ctob_car_owner_clue_transform_ymd
where dt = '${date_y_m_d}' 
and ctob_busi_type_code = 1
) t2 on t1.clue_id = t2.clue_id -- 维度表
where audit_to_onshlve >= 0
group by 1,2,3
)

select t1.*,coalesce(q.quantity_set,0) quantity_set,
time_all,check_time,wait_time,running_time,verify_time,audit_to_onshlve_time,no_value_run_time,
onshelf_time_all
from
(
select dt,channel_level,toufang_type,
sum(case when is_salvage = 0 and is_75_city = '是' then clue_num else 0 end) as clue_num,
sum(case when is_75_city = '是' then evaluate_num else 0 end) as evaluate_num,
sum(case when cb_sale_type='tob' then onshelf_num else 0 end) as onshelf_num ,
SUM(CASE WHEN cb_sale_type='tob' THEN onshelf_num * COALESCE(t2_norm.single_listing_revenue_coef, t2_max.single_listing_revenue_coef) ELSE 0 END) AS standard_onshelf_num
from c1_channel a -- 和维度表关联过的线索量 工单量 上架量 
-- 规则1：正常判断 a.dt 是否落在 [start_date, end_date] 区间内
LEFT JOIN guazi_dw_import.dim_mkt_channel_listing_std_coef t2_norm 
       ON a.new_type = t2_norm.first_level_category
      AND a.dt >= t2_norm.start_date 
      AND a.dt <= t2_norm.end_date
-- 规则2：如果 a.dt 超出了该分类最大的 end_date，则匹配兜底表
LEFT JOIN coef_max t2_max 
       ON a.new_type = t2_max.first_level_category
      AND a.dt > t2_max.max_end_date
group by 1,2,3
) t1
left join
(
select dt,channel_level,toufang_type,
(sum(check_time_cnt)+sum(wait_time_cnt)+sum(running_time)+sum(verify_time_cnt)+sum(audit_to_onshlve))/3600 as time_all,
sum(check_time_cnt)/3600 as check_time,
sum(wait_time_cnt)/3600 as wait_time,
sum(running_time)/3600 as running_time,
sum(verify_time_cnt)/3600 as verify_time,
sum(audit_to_onshlve)/3600 as audit_to_onshlve_time,
sum(no_value_run_cnt)/3600 as no_value_run_time
from evaluate_time_2 a  
group by 1,2,3
) t2 on t1.dt = t2.dt and t1.channel_level = t2.channel_level and t1.toufang_type = t2.toufang_type -- 所有时长
left join onshelf_time o on o.dt=t1.dt  -- 单独看的上架时长
and o.channel_level=t1.channel_level
and o.toufang_type=t1.toufang_type
left join (select prepay_time,channel_level,toufang_type ,sum(quantity_set)quantity_set from quantity_set_clue group by 1,2,3 )q  -- 净已定
on q.prepay_time = t1.dt and t1.channel_level = q.channel_level and t1.toufang_type = q.toufang_type