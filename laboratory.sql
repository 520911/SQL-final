set search_path to bookings

--1. В каких городах больше одного аэропорта?
/*
 Используется группировка по названию города и с помощью
 оператора having вывожу только те города, в которых более одного аэропорта 
 */
select a.city as "Город"
from airports a 
group by a.city 
having count(airport_code) > 1

-- 2. В каких аэропортах есть рейсы, 
--    выполняемые самолетом с максимальной дальностью перелета? Подзапрос
/*
 В подзапросе выподняем сортировку по максимальной дальности полета самолета и оставляем первую строчку
 в основном запросе присоединяем к таблице аэропортов таблицу полетов и 
 указываем условие, что ключ самолета должен быть равен результату подзапроса, т.е. одному значению
 */
select distinct a.airport_name as "Название аэропорта"
from airports a 
join flights f on a.airport_code = f.departure_airport 
where f.aircraft_code = (select aircraft_code 
							from aircrafts a
							order by "range" desc
							limit 1)

-- 3. Вывести 10 рейсов с максимальным временем задержки вылета. Оператор LIMIT
--    
/*
 Вывожу с операторе select только id рейса и задержку, которая считается простым вычитанием 
 из времени отправки по расписанию и фактического времени отправки.
 Так же убираю null из столбца по фактической отправки и ограничиваю вывод 10 записями, сортируя по убыванию
 */
select f.flight_id "ID рейса",
(f.actual_departure - f.scheduled_departure) as "Задержан на"
from flights f 
where f.actual_departure is not null
order by "Задержан на" desc
limit 10						

-- 4. Были ли брони, по которым не были получены посадочные талоны? Верный тип JOIN
--    
/*
 В операторе case выводим только одно конечное значение да или нет, в качестве ответа на вопрос
 В запросе присоединяем таблицу tickets и полностью присоединяем таблицу boarding_passes
 для тго, что бы вывести все значения в получении талонов на посадку, даже те, которые null т.е. талон не получен
 */
select 
case 
	when count(bp.boarding_no is null) > 0 then 'Да'
	else 'Нет'
	end as "Результат"
from bookings b 
join tickets t on b.book_ref = t.book_ref 	
left join boarding_passes bp on t.ticket_no = bp.ticket_no 
where bp.boarding_no is null						
							

-- 5. Найдите свободные места для каждого рейса, их % отношение к общему количеству мест в самолете.
--    Добавьте столбец с накопительным итогом - суммарное накопление количества вывезенных пассажиров из каждого аэропорта на каждый день. 
--    Т.е. в этом столбце должна отражаться накопительная сумма - сколько человек уже вылетело из данного аэропорта на этом или более ранних рейсах за день. 
-- - Оконная функция, Подзапросы или/и cte
/*
 СТЕ max_seats считает максимальное количество мест во всех видах самолета и группирует по коду самолета
 СТЕ flights_seats считает количество использованных мест в самолете через таблицу boarding_passes и так же отсеивает рейсы,
 которые находятся в статусе либо в полете либо прибывшие
 Основной запрос выводит номер рейса, максимальное количество мест в самолетах, количество занятых мест,
 количество свободных мест, процент отношения свободных мест к общему количеству, актуальную дату вылета,
 аэропорт вылета и накопительную сумму сгруппированную по аэропорту вылета и дню акруальной даты вылета и сотрирует это значение
 по актуальной дате вылета для получения накопительной суммы.
 Так же в основном запросе используется джойн двух CTE по номеру рейса и сортировка по аэропорту вылета и дате для проверки накопительной суммы пассажиров за день
 */
with max_seats as(
select s.aircraft_code, count(seat_no) as max_seat_count
from seats s 
group by s.aircraft_code),
	flights_seats as(
	select f.flight_no, f.aircraft_code, f.actual_departure, f.departure_airport,
	count(bp.seat_no) as use_seats_count
	from flights f 
	join boarding_passes bp on f.flight_id = bp.flight_id
	group by f.flight_id 
	having f.status in ('Arrived', 'Departed'))
		select fse.flight_no as "Номер рейса",
		ms.max_seat_count as "Максимальное количество мест", 
		fse.use_seats_count as "Количество занятых мест",
		(ms.max_seat_count - fse.use_seats_count) as "Количество свободных мест",
		round((ms.max_seat_count - fse.use_seats_count) * 100. / ms.max_seat_count, 2) || ' ' || '%' as "% соотношения свободных мест к общему количеству",
		fse.actual_departure::date,
		fse.departure_airport,
		sum(fse.use_seats_count) over(partition by fse.departure_airport, fse.actual_departure::date order by fse.actual_departure)
		from flights_seats fse
		join max_seats ms on fse.aircraft_code = ms.aircraft_code
		order by fse.departure_airport, fse.actual_departure::date
		
-- 6. Найдите процентное соотношение перелетов по типам самолетов от общего количества. 
--    Подзапрос
--    Оператор ROUND
/*
 С помощью вложенного запроса считаем общее количество вылетов, которые уже состоялись
 В основном запросе так же отсеиваем рейсы, которые еще не состоялись
 Считаем проценты по школьной формуле: количество полетов по каждой модели самолета умножаем на 100 и делим на общее количество в подзапросе
 */		
select a.model as "Модель самолета", 
count(f.flight_id) as "Количество полетов на каждой модели самолета",
round(count(f.flight_id) * 100. / (select count(f.flight_id) from flights f where f.actual_departure is not null), 2) || '%' as "% полетов на модели самолета"
from flights f
join aircrafts a on f.aircraft_code = a.aircraft_code 
where f.actual_departure is not null
group by a.aircraft_code 

-- 7. Были ли города, в которые можно добраться бизнес - классом дешевле, 
--    чем эконом-классом в рамках перелета? 
--    CTE
/*
 Использовал 2 вложенных  СТЕ 
 buis_min - для вычисления минимальной цены на билеты бизнесс класса
 econom_max - для вычисления максимальной цены эконом класса
 В СТЕ main соединил два СТЕ и вывел flight_id там, где эконом класс дороже бизнеса
 В основном запросе присоединил основное СТЕ к представлению flights_v по flight_id
 И отсортаровал по status = 'Arrived'. Получилось, что эконом класс не был дороже бизнеса ни в одном законченном рейсе
 */
with main as (
	with buis_min as (
		select tf.flight_id, min(tf.amount) as min_a
		from ticket_flights tf 
		where tf.fare_conditions = 'Business'
		group by tf.flight_id),
		econom_max as (
			select tf.flight_id, max(tf.amount) as max_a
			from ticket_flights tf 
			where tf.fare_conditions = 'Economy'
			group by tf.flight_id)
				select em.flight_id,
				bm.min_a as mix_cost_business,
				em.max_a as max_cost_economy
				from buis_min bm
				join econom_max em on bm.flight_id = em.flight_id
				where em.max_a > bm.min_a)
					select m.flight_id, fv.arrival_city 
					from main m
					join flights_v fv on m.flight_id = fv.flight_id 
					where fv.status = 'Arrived'
	
-- 8. Между какими городами нет прямых рейсов? 
--    Декартово произведение в предложении FROM
--    Самостоятельно созданные представления
--    Оператор EXCEPT
/*
Создание представления где результатом будет все города имеющие прямые рейсы
В основном запросе делаем полное пересечение всех городов и вычитаем те, у кого есть прямые рейсы
 */
create view forward_cty as 
	select a.city as dep_a, a2.city as arr_a  
	from airports a 
	join flights f on a.airport_code = f.departure_airport 
	join airports a2 on f.arrival_airport = a2.airport_code


select a.city, a2.city 
from airports a 
cross join airports a2 
where a.city != a2.city 
except 
select * from forward_cty

-- 9. Вычислите расстояние между аэропортами, связанными прямыми рейсами, 
--    сравните с допустимой максимальной дальностью перелетов  в самолетах, обслуживающих эти рейсы 
--    Оператор RADIANS или использование sind/cosd
--    CASE 
/*
В СТЕ рассчитывается расстояние месжду аэропортами в городах, имеющих прямые рейсы.
В основном запросе присоединяется таблица с моделями самолетов и максимальным расстояние полета самолетов
В CASE сравнивается расстояние между городами и максимально возможное по характеристикам самолета
 */					
with city_range as (
	select distinct f.aircraft_code,
	round((acos(sind(a.latitude) * sind(a2.latitude) +
	cosd(a.latitude) * cosd(a2.latitude) * cosd(a.longitude - a2.longitude)) * 6371)::numeric, 2) as range_a
	from airports a 
	join flights f on a.airport_code = f.departure_airport 
	join airports a2 on f.arrival_airport = a2.airport_code
	where a.city > a2.city 
	order by range_a)
		select a.model as "Модель самолета", 
		cr.range_a as "Расстояние между аэропортами",
		a.range as "Масимальное расстояние полета самолета",
		case 
			when cr.range_a < a.range then 'Расстояние меньше возможности самолета'
			else 'Расстояние больше возможности самолета'
			end as "Результат"
		from city_range cr
		join aircrafts a on cr.aircraft_code = a.aircraft_code 
		
