/*
文件: 经营-漏斗2-圈车_首上架_实际上架.sql
指标: 自营B圈车量|自营C圈车量|虚拟寄售圈车量|实体寄售圈车量|首上实体寄售量|首上虚拟寄售量|首上自营B量|首上C2B量|首上自营C量|T0-实体寄售C端上架量|T1-实体寄售C端上架量|T3-实体寄售C端上架量|T5-实体寄售C端上架量|T7-实体寄售C端上架量|T14-实体寄售C端上架量
业务: C1车源圈车到上架的转化漏斗分析
场景: 统计C1车源在不同圈车渠道圈车量、首上架量、实体寄售的T1~T14天上架量
标签: 漏斗|圈车|上架|寄售|自营|C1|转化|经营周报|首上架
维度: 自营收车圈车日期|寄售圈车日期|上架日期
核心表: dw_ctob_c1_car_source_ymd|dw_car_platform_quality_supply_detail_ymd
作者: 文国庆
描述: 圈车到首上架的转化漏斗
*/
-- 全量圈车：按圈车日期汇总 圈车量 & 圈车类型 & 首上架量 & 实际上架量
WITH car_collect AS (
    SELECT DISTINCT
        SUBSTR(car_collect_created_time, 1, 10) AS collect_dt,   -- 自营收车圈车日期
        SUBSTR(first_consign_submit_time, 1, 10) AS consign_dt,  -- 寄售圈车日期
	    SUBSTR(onshelf_time,1,10) onshelf_dt,
        CASE WHEN car_collect_platform = 1 THEN 1 END AS is_self_b_collect,
        CASE WHEN car_collect_platform IN (2, 3) THEN 1 END AS is_self_c_collect,
        CASE WHEN consign_choose_type IN (1, 2) THEN 1 END AS is_virtual_consign,
        CASE WHEN consign_choose_type = 2 THEN 1 END AS is_physical_consign,
        clue_id,
        first_onshelf_biz_line
    FROM guazi_dw_dw.dw_ctob_c1_car_source_ymd t1
    WHERE t1.dt = '${date_y_m_d}' 
      AND t1.is_c1_clue = 1 
      AND (SUBSTR(car_collect_created_time, 1, 10) >= '${start}'  -- 自营收车圈车时间
        or SUBSTR(first_consign_submit_time, 1, 10) >= '${start}'-- 寄售圈车时间
		or SUBSTR(onshelf_time, 1, 10) >= '${start}') -- 上架时间
),
actual_onshelf AS ( -- 实体寄售实际上架时间
    SELECT DISTINCT
		dt
        ,clue_id
    FROM guazi_dw_dw.dw_car_platform_quality_supply_detail_ymd
    WHERE dt >= '${start}'
      AND SUBSTRING(cb_first_shelf_time, 1, 10) = dt
      AND clue_type = 'bc同售'
      AND valid_tags LIKE '%1554%'
)

SELECT 
    a.collect_dt AS `自营收车圈车日期`,
    a.consign_dt AS `寄售圈车日期`,
	a.onshelf_dt as `上架日期`,
    COUNT(DISTINCT CASE WHEN a.is_self_b_collect = 1 THEN a.clue_id END) AS `自营B圈车量`,
    COUNT(DISTINCT CASE WHEN a.is_self_c_collect = 1 THEN a.clue_id END) as `自营C圈车量`,
    COUNT(DISTINCT CASE WHEN a.is_virtual_consign = 1 THEN a.clue_id END) as `虚拟寄售圈车量`,
    COUNT(DISTINCT CASE WHEN a.is_physical_consign = 1 THEN a.clue_id END) as `实体寄售圈车量`,

    COUNT(DISTINCT CASE WHEN a.first_onshelf_biz_line = 'C2C独售-门店' THEN a.clue_id END) AS `首上实体寄售量`,
    COUNT(DISTINCT CASE WHEN a.first_onshelf_biz_line = 'C2C独售-虚拟' THEN a.clue_id END) AS `首上虚拟寄售量`,
    COUNT(DISTINCT CASE WHEN a.first_onshelf_biz_line = '自营B'       THEN a.clue_id END) AS `首上自营B量`,
    COUNT(DISTINCT CASE WHEN a.first_onshelf_biz_line = 'C2B'         THEN a.clue_id END) AS `首上C2B量`,
    COUNT(DISTINCT CASE WHEN a.first_onshelf_biz_line = '自营C'       THEN a.clue_id END) AS `首上自营C量`,
	
	IFNULL(COUNT(DISTINCT CASE WHEN b.dt = a.consign_dt THEN b.clue_id END),0) AS `T0-实体寄售C端上架量`,
	IFNULL(COUNT(DISTINCT CASE WHEN b.dt <= DATE_ADD(a.consign_dt, INTERVAL 1 DAY) THEN b.clue_id END),0) AS `T1-实体寄售C端上架量`,
	IFNULL(COUNT(DISTINCT CASE WHEN b.dt <= DATE_ADD(a.consign_dt, INTERVAL 3 DAY) THEN b.clue_id END),0) AS `T3-实体寄售C端上架量`,
	IFNULL(COUNT(DISTINCT CASE WHEN b.dt <= DATE_ADD(a.consign_dt, INTERVAL 5 DAY) THEN b.clue_id END),0) AS `T5-实体寄售C端上架量`,
	IFNULL(COUNT(DISTINCT CASE WHEN b.dt <= DATE_ADD(a.consign_dt, INTERVAL 7 DAY) THEN b.clue_id END),0) AS `T7-实体寄售C端上架量`,
	IFNULL(COUNT(DISTINCT CASE WHEN b.dt <= DATE_ADD(a.consign_dt, INTERVAL 7 DAY) THEN b.clue_id END),0) AS `T14-实体寄售C端上架量`

FROM car_collect a
LEFT JOIN actual_onshelf b ON a.clue_id = b.clue_id and a.consign_dt <= b.dt
GROUP BY 1,2,3
ORDER BY 1,2,3
