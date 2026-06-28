/*
文件: 截面数据源4-圈车.sql
指标: 线索量clue_num|上架量clue_num_shelf
业务: C1圈车线索及上架转化统计
场景: 统计C1车源圈车线索量及上架量，按圈车维度汇总
标签: 截面|圈车|线索量|上架量|C1|C端自营|B端自营|C2C|转化
维度: 圈车时间collect_dt|圈车渠道car_collect_platform
核心表: dw_ctob_evaluate_task_ymd|dwb_cars_car_source_tag_day|dim_ctob_auction_car_source_ymd
作者: 未知
描述: 分别统计圈车线索量及对应上架量
*/
---截面数据源4:圈车
select
collect_dt -- 圈车时间
,car_collect_platform
,clue_num
,clue_num_shelf
from 
(
select 
	collect_dt
	,car_collect_platform
	,count(distinct t1.clue_id) as clue_num
	,count(distinct t2.clue_id) as clue_num_shelf
from 
(
	select 
		substr(car_collect_created_time, 1, 10) as collect_dt
		,case when car_collect_platform = 2 then 'C端自营圈车' 
	when car_collect_platform = 1 then 'B端自营圈车' end as car_collect_platform
		,clue_id
	from guazi_dw_dw.dw_ctob_evaluate_task_ymd
	where dt = '${date_y_m_d}'
	and car_collect_status = 1 -- 圈车
	and substr(car_collect_created_time, 1, 10) between '${start}' AND '${date_y_m_d}'
	group by 1,2,3
)t1
left join 
(
	SELECT
		SUBSTRING(onshelf_time, 1, 10) AS dt
		,clue_id
	FROM guazi_dw_dwd.dim_ctob_auction_car_source_ymd
	WHERE dt = '${date_y_m_d}'
	AND SUBSTRING(onshelf_time, 1, 10) BETWEEN '${start}' AND '${date_y_m_d}'
	AND ctob_busi_type_code IN (0,1) --- 所有C1新上架量
	group by 1,2
)t2 on t1.clue_id = t2.clue_id and t1.collect_dt = t2.dt
group by 1,2

union all

select 
	collect_dt
	,'C2C圈车' as car_collect_platform
	,count(distinct t1.clue_id) as clue_num
	,count(distinct t2.clue_id) as clue_num_shelf
from 
(
	select 
		substr(created_at, 1, 10) as collect_dt
		,clue_id
	from guazi_dw_dwb.dwb_cars_car_source_tag_day
	where dt = '${date_y_m_d}'
	and substr(created_at, 1, 10) between '${start}' AND '${date_y_m_d}'
	and tag = 1563
	group by 1,2
)t1
left join 
(
	SELECT
		SUBSTRING(onshelf_time, 1, 10) AS dt
		,clue_id
	FROM guazi_dw_dwd.dim_ctob_auction_car_source_ymd
	WHERE dt = '${date_y_m_d}'
	AND SUBSTRING(onshelf_time, 1, 10) BETWEEN '${start}' AND '${date_y_m_d}'
	AND ctob_busi_type_code IN (0,1) --- 所有C1新上架量
	group by 1,2
)t2 on t1.clue_id = t2.clue_id and t1.collect_dt = t2.dt
group by 1,2
)a
 