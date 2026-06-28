/*
文件: 数据源4-建单到上架cohort.sql
指标: 建单量|T0上架量|T1上架量|T2上架量|T3上架量|T4上架量|T5上架量|T6上架量|T7上架量
业务: C1评估工单到上架的cohort转化分析
场景: 按评估创建日期（cohort）统计C1车源在不同时间窗口（T0~T7天）的累计上架量，用于分析工单创建后的上架转化效率
标签: 建单|上架|cohort|转化|C1|评估工单
维度: dt（评估创建日期）|city_level（城市等级）|city_name（城市）
核心表: dw_ctob_evaluate_task_ymd|dim_ctob_auction_car_source_ymd|dim_com_city_ymd
作者: 未知
描述: 按评估创建日期统计C1工单在T0~T7天的累计上架量
*/
-- 数据源4：建单到上架cohort
-- 工单
with t1 as (
    select
        clue_id,
        city_id,
        substr(evaluate_create_time, 1, 10) dt  -- 评估创建时间
    from guazi_dw_dw.dw_ctob_evaluate_task_ymd  -- 车速拍评估工单表
    where dt = '${date_y_m_d}'
        and substr(evaluate_create_time, 1, 10) between '${start}' and '${date_y_m_d}'
        and ctob_busi_type = '一口价'  -- 一口价是C线索
),
-- 上架  
t2 as (
    select 
        clue_id,
        city_id,
        substr(onshelf_time, 1, 10) dt  -- 这个是tob的上架
    from guazi_dw_dwd.dim_ctob_auction_car_source_ymd  -- B端车源信息维表
    where dt = '${date_y_m_d}'
        and ctob_busi_type_code in (1)  -- 和看板比对，修改条件
		-- ctob_busi_type_code拍卖业务类型：0:其他 1:C线索 2:经销商C线索 3:经销商B线索 4:开放平台 5:斩仓车 6:淘车 7:B2C同售B2B 8:B2C满7天自动同售B2B 9 B收车 10C收车
),
t3 as (
    select 
        city_id,
        city_level,  -- 城市等级
        city_name,
        province_short_name --省
    from guazi_dw_dwd.dim_com_city_ymd  -- 城市维表
    where dt = '${date_y_m_d}'
)	 
select 
    t1.dt, 
    t3.city_level, 
    t3.city_name, 
    count(distinct t1.clue_id) as `建单量`, 
    count(distinct case when datediff(cast(t2.dt as date), cast(t1.dt as date)) = 0 then t2.clue_id end) as `T0上架量`, -- 工单~上架，落到上架的量
    count(distinct case when datediff(cast(t2.dt as date), cast(t1.dt as date)) <= 1 then t2.clue_id end) as `T1上架量`,
    count(distinct case when datediff(cast(t2.dt as date), cast(t1.dt as date)) <= 2 then t2.clue_id end) as `T2上架量`,
    count(distinct case when datediff(cast(t2.dt as date), cast(t1.dt as date)) <= 3 then t2.clue_id end) as `T3上架量`,
    count(distinct case when datediff(cast(t2.dt as date), cast(t1.dt as date)) <= 4 then t2.clue_id end) as `T4上架量`,
    count(distinct case when datediff(cast(t2.dt as date), cast(t1.dt as date)) <= 5 then t2.clue_id end) as `T5上架量`,
    count(distinct case when datediff(cast(t2.dt as date), cast(t1.dt as date)) <= 6 then t2.clue_id end) as `T6上架量`,
    count(distinct case when datediff(cast(t2.dt as date), cast(t1.dt as date)) <= 7 then t2.clue_id end) as `T7上架量`
from t1
left join t2 on t1.clue_id = t2.clue_id 
left join t3 on t1.city_id = t3.city_id
-- where t2.clue_id is not null
group by 1, 2, 3