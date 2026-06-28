/*
文件: 数据源3-人力数据.sql
指标: 检测师在职人数|检测师有效在职人数|检测师可用人数|检测师可用pd|检测师实排pd|检测师预排pd|检测师在岗pd|打卡人数|应打卡人数
业务: C1检测师人力数据分析
场景: 按日期、城市维度统计检测师的人力情况，包括在职人数、可用人数、排班情况、打卡情况等，用于评估检测师的人效
标签: 检测师|人力|在职|可用|排班|打卡|pd|人效|C1|评估
维度: dt（日期）|city_name（城市）|city_level（城市等级）
核心表: dm_ctob_evaluator_date_work_detail_inc_ymd|dim_com_city_ymd
作者: 宋明瑞
描述: 按日期、城市统计检测师在职、可用、排班、打卡等人力数据
*/
-- 数据源3：人力数据
with t1 as (
	select *
	FROM guazi_dw_dm.dm_ctob_evaluator_date_work_detail_inc_ymd  -- 履约评估工单人效
	where dt between '${start}' and '${date_y_m_d}')
,t2 as (
	select 
	city_id
	,city_level
	,city_name as city_name
	,province_short_name
    from guazi_dw_dwd.dim_com_city_ymd --城市维表
    where dt = '${date_y_m_d}'
)
SELECT
      dt
	  ,t2.city_name
	  ,t2.city_level
	  ,sum(COALESCE(evaluator_num, 0)) `检测师在职人数`
      ,((sum(COALESCE(evaluator_num, 0)) - sum(COALESCE(holiday_evaluator_num, 0))) - sum(COALESCE(pending_change_evaluator_num, 0))) `检测师有效在职人数`
      ,sum(create_usable_evaluator_num) `检测师可用人数`
      ,sum(create_usable_evaluator_pd) `检测师可用pd`
      ,sum((CASE WHEN date_day >= pre_work_count_day THEN pre_work_count_day ELSE date_day END)) `检测师实排pd`
      ,sum(pre_work_count_day) `检测师预排pd`
      ,sum(date_day) `检测师在岗pd`
      ,sum(clock_user_cnt) `打卡人数`
      ,sum(need_clock_user_cnt) `应打卡人数`
from t1
left join t2 on t1.city_id=t2.city_id
where  dt BETWEEN '${start}' AND '${date_y_m_d}'
group by 1,2,3