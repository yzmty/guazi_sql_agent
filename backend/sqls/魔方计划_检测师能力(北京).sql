/*
文件: 魔方计划_检测师能力(北京).sql
指标: 工单量|C圈车量|B圈车量|零售上架量|非零售上架量|自营C圈车量|C2C虚拟圈车量|C2C实体圈车量|自营B圈车量|首上自营C量|首上虚拟寄售量|首上实体寄售量|首上自营B量|首上C2B量
业务: 检测师转化能力分析
场景: 统计检测师的评估工单在创建后7天内的圈车转化和首上架情况，区分C圈车/B圈车、零售/非零售、各圈车类型及首上架渠道，用于评估检测师的圈车后的转化效率
标签: 检测师|圈车|上架|C圈车|B圈车|零售|自营C|C2C|自营B|首上架|C1|人效|魔方计划|线索分层|线索|评估工单
维度: city_name（城市）|department_name（部门）|user_name（检测师姓名）|position_name（岗位）
核心表: dw_ctob_evaluate_task_ymd|dw_ctob_c1_car_source_ymd|dim_com_city_ymd|dim_com_struct_dept_user_ymd
作者: 未知
描述: 按检测师统计评估工单创建后7天内的圈车转化和首上架渠道分布，主要用来评估检测师能力
*/
-- 工单
with t1 as (
    select
        clue_id,
        city_id,
		city_level,
		collect_seller_id,
        substr(evaluate_create_time, 1, 10) dt,
        evaluate_create_time
    from guazi_dw_dw.dw_ctob_evaluate_task_ymd
    where dt = '${date_y_m_d}'
        and substr(evaluate_create_time, 1, 10) between '${start}' and '${date_y_m_d}'
        and ctob_busi_type = '一口价'
		and ctob_busi_type_code = 1
)
,
clue_info as (
        SELECT  
            t1.clue_id,
            COALESCE(t1.clue_id_self,t1.clue_id) as clue_id_second,
            substr(onshelf_time, 1, 10) AS onshelf_dt,
            onshelf_time,
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
			CASE WHEN car_collect_platform in (2,3) then 1 else 0 end as `是否自营C`,
			CASE when consign_choose_type in (1,2) then 1 else 0 end as `是否C2C虚拟`,
			CASE when consign_choose_type =2 then 1 else 0 end as `是否C2C实体`,
			CASE when car_collect_platform =1 then 1 else 0 end as `是否自营B`,
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
        AND t1.is_c1_clue = 1
        and substr(onshelf_time,1,10) is not null
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
c.city_name,
t.department_name,
t.user_name,
t.user_id ,
t.position_name,
count(distinct t1.clue_id) as `工单量`,

count(distinct case when b.circle_type = 'C圈车' then t1.clue_id else null end) as `C圈车量`,
count(distinct case when b.circle_type = 'B圈车' then t1.clue_id else null end) as `B圈车量`,
-- 零售/非零售
count(distinct case when b.clue_id is not null and b.first_onshelf_type_detail = '零售' then t1.clue_id else null end) as `零售上架量`,
count(distinct case when b.clue_id is not null and b.first_onshelf_type_detail = '非零售' then t1.clue_id else null end) as `非零售上架量` ,

count(distinct case when b.`是否自营C` = 1 then t1.clue_id else null end) as `自营C圈车量`,
count(distinct case when b.`是否C2C虚拟` = 1 then t1.clue_id else null end) as `C2C虚拟圈车量`,
count(distinct case when b.`是否C2C实体` = 1 then t1.clue_id else null end) as `C2C实体圈车量`,
count(distinct case when b.`是否自营B` = 1 then t1.clue_id else null end) as `自营B圈车量`,

count(distinct case when b.clue_id is not null and b.first_onshelf_type = '首上自营C' then t1.clue_id else null end) as `首上自营C量`,
count(distinct case when b.clue_id is not null and b.first_onshelf_type = '首上虚拟寄售' then t1.clue_id else null end) as `首上虚拟寄售量`,
count(distinct case when b.clue_id is not null and b.first_onshelf_type = '首上实体寄售' then t1.clue_id else null end) as `首上实体寄售量`,
count(distinct case when b.clue_id is not null and b.first_onshelf_type = '首上自营B' then t1.clue_id else null end) as `首上自营B量`,
count(distinct case when b.clue_id is not null and b.first_onshelf_type = '首上C2B' then t1.clue_id else null end) as `首上C2B量`

from t1 
left join clue_info b on t1.clue_id = b.clue_id
    and datediff(substr(b.onshelf_time,1,10), substr(t1.evaluate_create_time,1,10)) <= 7 
    and datediff(substr(b.onshelf_time,1,10), substr(t1.evaluate_create_time,1,10)) >= 0 
left join city c on t1.city_id = c.city_id
left join task t on t1.collect_seller_id = t.user_id
where t.department_name in 
('北京检测一组','北京检测二组','北京检测三组','北京检测四组','北京检测五组','北京检测六组')
group by 
c.city_name,
t.department_name,
t.user_name,
t.position_name