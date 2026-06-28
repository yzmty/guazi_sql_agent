/*
文件: 数据源-人力成本时长明细.sql
指标: clue_num（线索量）|evaluate_num（工单量）|onshelf_num（上架量）|quantity_set（净已定量）|time_all（总时长）|check_time（检测时长）|wait_time（等待时长）|running_time（跑动时长）|verify_time（审核时长）|audit_to_onshlve_time（审核到上架时长）|no_value_run_time（枉跑时长）|onshelf_time_all（上架总时长）
业务: C1线索转化全链路时长分析
场景: 按日期、渠道、投放类型统计C1车源的线索量、工单量、上架量、净已定量，以及各环节时长（检测/等待/跑动/审核/审核到上架/枉跑）
标签: 线索|工单|上架|净已定|时长|检测|审核|枉跑|C1|渠道|投放|转化漏斗
维度: dt（日期）|channel_level（渠道）|toufang_type（投放类型）
核心表: dm_ctob_clue_detail_transform_csd_inc_ymd|dwd_ctob_evaluate_sub_task_ymd|dwd_ctob_car_owner_clue_transform_ymd|dw_ctob_c1_tob_toc_appoint_detail_ymd|dw_ctob_c1_car_source_ymd
作者: 宋明瑞|杨悦芳
描述: 按渠道和投放类型统计C1线索量、工单量、上架量、净已定量及各环节时长
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
and substr(distribute_time,1,10) between '${start}' and '${end}'
and ctob_busi_type_code = 1
),
-- 作为维度表
clue_info as (
select clue_id,channel_level1,channel_level2,toufang_type,
case when channel_level2 = '非主端' then '非主端-端产品'
when channel_level1 = '非端产品' then '表单'
when channel_level1 = '商务拓展' then '商务'
when channel_level1 = '端产品' then '主端'
else channel_level1 end as channel_level
from guazi_dw_dwd.dwd_ctob_car_owner_clue_transform_ymd
where dt = '${date_y_m_d}' 
and ctob_busi_type_code = 1
),
-- 线索量 工单量 上架量
clue_task_onshelf as (
select *
FROM guazi_dw_dm.dm_ctob_clue_detail_transform_csd_inc_ymd         
WHERE dt BETWEEN '${start}' AND '${end}' 
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
select a.dt,b.channel_level,b.toufang_type  , cb_sale_type, 
a.is_salvage, a.is_75_city , sum(clue_num)clue_num ,
sum(evaluate_num )evaluate_num,
sum(onshelf_num)onshelf_num 
from clue_task_onshelf a
left join clue_info b on a.clue_id = b.clue_id
group by 1,2,3,4 ,5 ,6
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
and substr(distribute_time,1,10) between '${start}' and '${end}'
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
sum(case when cb_sale_type='tob' then onshelf_num else 0 end) as onshelf_num 
from c1_channel a -- 和维度表关联过的线索量 工单量 上架量 
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