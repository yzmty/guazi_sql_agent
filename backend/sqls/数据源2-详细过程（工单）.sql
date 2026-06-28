/*
文件: 数据源2-详细过程（工单）.sql
指标: 评估工单量|评估工单量(剔除回捞)|时间受限建单成功量|时间受限建单失败量|T0~T8建单量|预约工单量|预约分配前改约到非当天工单量|预约分配前改约到当天工单量|预约分配前取消工单量|预约分配前改约地址工单量|分配溢出工单量|末次分配工单量|建单可用pd|实排pd|预排人数|实排人头数|分配子工单量|冲突工单量|出发量|到达量|开始检测量|上架审核通过量|出发子工单量|到达子工单量|开始检测子工单量|上架审核通过子工单量|上架量|跑动时长|等待时长|检测时长|审核时长|审核上架时长|总时长
业务: C1评估工单全链路分析，包括时长
场景: 按日期、是否投放、城市维度统计C1评估工单时长和建单量
标签: 评估工单|建单|预约|分配|出发|到达|检测|审核|上架|时长|C1|时长
维度: dt（日期）|是否投放|city_id|city_name|city_level
核心表: dm_ctob_evaluate_fence_city_index_stat_ymd|dim_com_city_ymd
作者: 宋明瑞
描述: 按日期、投放、城市统计C1评估工单各环节的时长以及建单量
*/
-- 数据源2：工单详细数据
SELECT 
	t1.*
	,t2.city_name
	,t2.city_level
	,t1.`跑动时长`+t1.`等待时长`+t1.`检测时长`+t1.`审核时长`+t1.`审核上架时长` as `总时长`
	 
FROM 
(
	SELECT 
		dt
		,is_ctob_toufang_desc AS `是否投放`
		,city_id
		-- ,ctob_busi_type_code
		,SUM(evaluate_task_num) AS `评估工单量`
		,SUM(evaluate_task_num_not_salvage) AS `评估工单量(剔除回捞)`
		,SUM(time_limited_evaluate_task_num) AS `时间受限建单成功量`
		,SUM(is_time_limited_create_fail) AS `时间受限建单失败量`
		,SUM(evaluate_task_num_t0) AS `T0建单量`
		,SUM(evaluate_task_num_t1) AS `T1建单量`
		,SUM(evaluate_task_num_t2) AS `T2建单量`
		,SUM(evaluate_task_num_t3) AS `T3建单量`
		,SUM(evaluate_task_num_t4) AS `T4建单量`
		,SUM(evaluate_task_num_t5) AS `T5建单量`
		,SUM(evaluate_task_num_t6) AS `T6建单量`
		,SUM(evaluate_task_num_t7) AS `T7建单量`
		,SUM(evaluate_task_num_t8) AS `T8建单量`
		,SUM(evaluate_book_task_num) AS `预约工单量`
		,SUM(evaluate_book_change_other_day_task_num) AS `预约分配前改约到非当天工单量`
		,SUM(evaluate_book_change_to_day_task_num) AS `预约分配前改约到当天工单量`
		,SUM(evaluate_book_cancel_before_distribute_task_num) AS `预约分配前取消工单量`
		,SUM(evaluate_book_change_address_before_distribute_task_num) AS `预约分配前改约地址工单量`
		,SUM(evaluate_distribut_full_task_num) AS `分配溢出工单量`
		,SUM(last_distribute_cnt) AS `末次分配工单量`
		,SUM(create_usable_evaluator_pd) AS `建单可用pd`
		,SUM(actual_work_count_pd) AS `实排pd`
		,SUM(pre_work_count) AS `预排人数`
		,SUM(actual_work_count) AS `实排人头数`
		,SUM(evaluate_distribut_sub_task_num) AS `分配子工单量`
		,SUM(evaluate_conflict_task_num) AS `冲突工单量`
		,SUM(evaluate_go_task_num) AS `出发量`
		,SUM(evaluate_arrive_task_num) AS `到达量`
		,SUM(evaluate_start_evaluate_task_num) AS `开始检测量`
		,SUM(evaluate_audit_pass_task_num) AS `上架审核通过量`
		,SUM(evaluate_go_sub_task_num) AS `出发子工单量`
		,SUM(evaluate_arrive_sub_task_num) AS `到达子工单量`
		,SUM(evaluate_start_evaluate_sub_task_num) AS `开始检测子工单量`
		,SUM(evaluate_audit_pass_sub_task_num) AS `上架审核通过子工单量`
		,SUM(evaluate_onshelve_num) AS `上架量`
		,SUM(running_time_cnt) AS `跑动时长`
		,SUM(wait_time_cnt) AS `等待时长`
		,SUM(check_time_cnt) AS `检测时长`
		,SUM(verify_time_cnt) AS `审核时长`
		,SUM(audit_to_onshlve_cnt) AS `审核上架时长`
	FROM guazi_dw_dm.dm_ctob_evaluate_fence_city_index_stat_ymd
	WHERE dt BETWEEN '${start}' and '${date_y_m_d}'
	and ctob_busi_type_code in (1) -- 限制一口价(C线索业务场景)
	GROUP BY 1,2,3
)t1
LEFT JOIN
(
   select 
	   city_id
	  ,city_level
	  ,city_name as city_name
	  ,province_short_name
   from guazi_dw_dwd.dim_com_city_ymd  -- 城市维表
   where dt = '${date_y_m_d}'
)t2 ON t1.city_id = t2.city_id