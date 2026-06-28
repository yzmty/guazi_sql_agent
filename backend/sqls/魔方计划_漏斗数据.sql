/*
文件: 魔方计划_漏斗数据.sql
指标: 工单日期|clue_id|检测师姓名|检测师id|大区|部门|岗位|车系|标签|新能源/燃油|价格带|里程|城市等级|城市名称|圈车类型|是否自营C|是否C2C虚拟|是否C2C实体|是否自营B|首上架渠道|零售/非零售|是否上架
业务: C1评估工单到上架的漏斗数据（魔方计划）
场景: 按工单创建日期统计C1评估工单的线索维度信息，关联检测师信息和7天内的上架转化情况，包括车系、标签、能源类型、价格带、里程、城市、圈车类型、首上架渠道等，用于魔方计划漏斗分析
标签: 评估工单|上架|漏斗|魔方计划|检测师|C1|圈车|首上架|价格带|燃油|新能源
维度: 工单日期|clue_id|检测师姓名|检测师id|大区|部门|岗位|车系|标签|新能源/燃油|价格带|里程|城市等级|城市名称|圈车类型|是否自营C|是否C2C虚拟|是否C2C实体|是否自营B|首上架渠道|零售/非零售|是否上架
核心表: dw_ctob_evaluate_task_ymd|dw_ctob_c1_car_source_ymd|dim_com_city_ymd|dim_com_struct_dept_user_ymd
作者: 宋明瑞|杨悦芳
描述: 从工单出发的漏斗的线索信息，用于线索分层
*/
-- 工单
with t1 as (
    select
        clue_id,
        city_id,
		city_level,
		collect_seller_id,
        substr(evaluate_create_time, 1, 10) dt,  -- 评估创建时间
        evaluate_create_time  -- 保留完整时间戳用于计算差值
    from guazi_dw_dw.dw_ctob_evaluate_task_ymd  -- 车速拍评估工单表
    where dt = '${date_y_m_d}'
        and substr(evaluate_create_time, 1, 10) between '${start}' and '${date_y_m_d}'
        and ctob_busi_type = '一口价'  -- 一口价是C线索
		and ctob_busi_type_code = 1
)
,
-- 上架
clue_info as (
        SELECT  
            t1.clue_id,
            COALESCE(t1.clue_id_self,t1.clue_id) as clue_id_second,
            substr(onshelf_time, 1, 10) AS onshelf_dt,
            onshelf_time,  -- 保留完整上架时间用于计算差值
            minor_category_name,
            tag_name,
            case 
            when road_haul > 0      and road_haul <= 30000  then 'a.(0-3万]'
            when road_haul > 30000  and road_haul <= 60000  then 'b.(3-6万]'
            when road_haul > 60000  and road_haul <= 100000 then 'c.(6-10万]'
            when road_haul > 100000 and road_haul <= 150000 then 'd.(10-15万]'
            when road_haul > 150000 and road_haul <= 200000 then 'e.(15-20万]'
            when road_haul > 200000                         then 'f.20万以上' 
            end as road_haul,
            if(fuel_type in (12, 13, 20), '新能源', '燃油车') as fuel_type,
            case
            when (seller_model_price * 1.0 / 10000) > 0   and (seller_model_price * 1.0 / 10000) <= 5   then 'a.(0-5]'
            when (seller_model_price * 1.0 / 10000) > 5   and (seller_model_price * 1.0 / 10000) <= 10  then 'b.(5-10]'
            when (seller_model_price * 1.0 / 10000) > 10  and (seller_model_price * 1.0 / 10000) <= 15  then 'c.(10-15]'
            when (seller_model_price * 1.0 / 10000) > 15  and (seller_model_price * 1.0 / 10000) <= 20  then 'd.(15-20]'
            when (seller_model_price * 1.0 / 10000) > 20  then 'e.(20+]'
            end model_price_region,
            evaluate_level,
            case when transfer_num < 3 then cast(transfer_num as string) else '3次及以上' end transfer_num,
            CASE WHEN car_collect_platform in (2,3) OR consign_choose_type IN (1, 2) THEN 'C圈车' ELSE 'B圈车' END AS circle_type,
			CASE WHEN car_collect_platform in (2,3) then 1 else 0 end  '是否自营C' ,
			CASE when consign_choose_type in (1,2) then 1 else 0 end '是否C2C虚拟',
			CASE when consign_choose_type =2 then 1 else 0 end '是否C2C实体',
			CASE when car_collect_platform =1 then 1 else 0 end '是否自营B' ,
            CASE
                WHEN first_onshelf_biz_line = 'C2C独售-虚拟' THEN '首上虚拟寄售'
                WHEN first_onshelf_biz_line =  'C2C独售-门店' THEN'首上实体寄售'
                WHEN first_onshelf_biz_line =  'C2B' THEN '首上C2B'
                WHEN first_onshelf_biz_line =  '自营C' THEN '首上自营C'
                WHEN first_onshelf_biz_line =  '自营B' THEN '首上自营B'
                ELSE first_onshelf_biz_line
            END AS first_onshelf_type ,
			CASE
			    WHEN first_onshelf_biz_line in( 'C2C独售-虚拟' , 'C2C独售-门店' ,'自营C') THEN '零售'
                ELSE '非零售'
            END AS first_onshelf_type_detail 
        FROM guazi_dw_dw.dw_ctob_c1_car_source_ymd t1
        WHERE t1.dt = '${date_y_m_d}'
        AND t1.is_c1_clue = 1 -- C1车源
        and substr(onshelf_time,1,10) is not null -- 已经上架 
)
,city AS (
    SELECT 
        city_id, city_name, short_name, domain, city_level,
        province_name, province_short_name
    FROM guazi_dw_dwd.dim_com_city_ymd
    WHERE dt = '${date_y_m_d}'
)
,task as (
select 
    user_id,
    user_name,
    region_name,
    store_name,
    department_name,
    group_name,
    position_name,
    job_indicators
from (
    select 
        user_id,
        user_name,
        region_name,
        store_name,
        department_name,
        group_name,
        position_name,
        job_indicators,
        ROW_NUMBER() OVER (
            PARTITION BY user_id ,department_name
            ORDER BY 
                CASE 
                    WHEN job_indicators = 'P' THEN 1
                    WHEN job_indicators = 'S' THEN 2
                    ELSE 3
                END
        ) as rn
    from guazi_dw_dwd.dim_com_struct_dept_user_ymd 
    where dt = '${date_y_m_d}' 
        and org_name = 'recheck'
        and user_tag = 0 -- 在职
) t
where rn = 1
)

select 
t1.dt as `工单日期`,
-- b.onshelf_dt 上架日期,
t1.clue_id,
user_name,
t1.collect_seller_id , -- 检测师id
region_name ,
department_name ,
position_name ,
b.minor_category_name, -- 车系
b.tag_name, -- 标签
b.fuel_type, -- 新能源/燃油
b.model_price_region, -- 价格带
b.road_haul, -- 里程
t1.city_level,
c.city_name ,
b.circle_type, -- 圈车
b.`是否自营C`,
b.`是否C2C虚拟`,
b.`是否C2C实体`,
b.`是否自营B` ,
b.first_onshelf_type,
b.first_onshelf_type_detail ,
case when b.clue_id is not null 
     and datediff(substr(b.onshelf_time,1,10), substr(t1.evaluate_create_time,1,10)) <= 7 
     and datediff(substr(b.onshelf_time,1,10), substr(t1.evaluate_create_time,1,10)) >= 0 
     then 1 else 0 end as is_onshelf -- 是否上架，上架时间-工单时间在0到7天之间
from t1 
left join clue_info b on t1.clue_id = b.clue_id
left join city c on t1.city_id = c.city_id
left join task t on t1.collect_seller_id = t.user_id