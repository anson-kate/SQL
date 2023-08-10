-- В каких городах больше одного аэропорта?
select city, count (airport_code)
from airports a 
group by city 
having count (airport_code)  > 1

-- В каких аэропортах есть рейсы, выполняемые самолетом с максимальной дальностью перелета?
select distinct airport_name, f.flight_no, a2.aircraft_code, a2.model 
from airports a
join flights f on a.airport_code = f.departure_airport 
join aircrafts a2 on a2.aircraft_code = f.aircraft_code 
where a2."range" = (select max (a3."range") from aircrafts a3);

-- Вывести 10 рейсов с максимальным временем задержки вылета
select 	f.flight_id, f.flight_no, f.scheduled_departure, f.actual_departure, 
	f.actual_departure - f.scheduled_departure "Çàäåðæêà"
from flights f
where f.actual_departure is not null
order by "Çàäåðæêà" desc
limit 10;

--Были ли брони, по которым не были получены посадочные талоны?
SELECT count(t2.book_ref)
FROM ticket_flights t 
JOIN flights f ON t.flight_id = f.flight_id 
join tickets t2 on t2.ticket_no = t.ticket_no
LEFT JOIN boarding_passes b ON t.ticket_no = b.ticket_no AND
t.flight_id = b.flight_id
where  f.actual_departure IS NOT null and b.boarding_no IS NULL;

select  count(t.book_ref) 
from  ticket_flights tf 
join tickets t on t.ticket_no = tf.ticket_no 
join flights f on f.flight_id = tf.flight_id 
left join boarding_passes bp on bp.ticket_no = t.ticket_no
where bp.boarding_no is null and f.actual_departure IS NOT null;

select count(distinct b.book_ref) 
from bookings b 
join tickets t on t.book_ref = b.book_ref 
left join boarding_passes bp on bp.ticket_no = t.ticket_no 
where bp.boarding_no is null;

--Найдите свободные места для каждого рейса, их % отношение к общему количеству мест в самолете.  
--Добавьте столбец с накопительным итогом - суммарное накопление количества вывезенных пассажиров из каждого
-- аэропорта на каждый день. 
--Т.е. в этом столбце должна отражаться накопительная сумма - сколько человек уже вылетело из
-- данного аэропорта на этом или более ранних рейсах за день.
with boarded as (
	select 
		f.flight_id,
		f.flight_no,
		f.aircraft_code,
		f.departure_airport,
		f.scheduled_departure,
		f.actual_departure,
		count(bp.boarding_no) boarded_count
	from flights f 
	join boarding_passes bp on bp.flight_id = f.flight_id 
	where f.actual_departure is not null
	group by f.flight_id 
),
max_seats_by_aircraft as(
	select 
		s.aircraft_code,
		count(s.seat_no) max_seats
	from seats s 
	group by s.aircraft_code 
)
select 
	b.flight_no,
	b.departure_airport,
	b.scheduled_departure,
	b.actual_departure,
	b.boarded_count,
	m.max_seats - b.boarded_count free_seats, 
	round((m.max_seats - b.boarded_count) / m.max_seats :: dec, 2) * 100 free_seats_percent,
	sum(b.boarded_count) over (partition by (b.departure_airport, b.actual_departure::date) order by b.actual_departure) "Íàêîïèòåëüíî ïàññàæèðîâ"
from boarded b 
join max_seats_by_aircraft m on m.aircraft_code = b.aircraft_code;


WITH ts AS
( SELECT f.flight_id, f.flight_no,
f.actual_departure, f.departure_airport, 
f.arrival_airport, f.aircraft_code,
count( tf.ticket_no ) AS fact_passengers,
( SELECT count( s.seat_no )
FROM seats s
WHERE s.aircraft_code = f.aircraft_code
) AS total_seats
FROM flights_v f JOIN ticket_flights tf
ON f.flight_id = tf.flight_id
WHERE f.status = 'Arrived'
GROUP BY 1, 2, 3, 4, 5, 6
)
SELECT ts.flight_id,
ts.flight_no,
ts.actual_departure,
ts.departure_airport,
ts.arrival_airport,
a.model,
ts.fact_passengers,
ts.total_seats,
round( (ts.total_seats - ts.fact_passengers)::numeric /
ts.total_seats::numeric, 2 ) *100 AS "% ìåñò ñâîáîäíî",
sum (ts.fact_passengers) over (partition by (ts.departure_airport, ts.actual_departure::date)
order by ts.actual_departure) "Íàêîïèòåëüíî ïàññàæèðîâ"
FROM ts JOIN aircrafts AS a
ON ts.aircraft_code = a.aircraft_code
ORDER BY ts.actual_departure;

--Найдите процентное соотношение перелетов по типам самолетов от общего количества
select 
	a.model "Модель самолета",
	count(f.flight_id) "Количество рейсов",
	round(count(f.flight_id) /
		(select count(f.flight_id)
		from flights f 
		where f.actual_departure is not null)::dec * 100, 2) "В % от общего числа"
from aircrafts a 
join flights f on f.aircraft_code = a.aircraft_code 
where f.actual_departure is not null
group by a.model;

SELECT a.model, count (*), 
       round (count(*)*100 / sum(count(*)) OVER(),2) as "В % от общего числа"
from aircrafts a 
join flights f on f.aircraft_code = a.aircraft_code 
where f.actual_departure is not null
group by a.model 
order by count(*)

--Были ли города, в которые можно  добраться бизнес - классом дешевле, чем эконом-классом в рамках перелета?
with min_and_max as(
	select 
		a.city dep_city,
		a2.city arr_city,
		tf.fare_conditions,
		case when tf.fare_conditions  = 'Business' then min(tf.amount) end b_min_amount,
		case when tf.fare_conditions  = 'Economy' then max(tf.amount) end e_max_amount
	from flights f 
	join ticket_flights tf on tf.flight_id = f.flight_id 
	join airports a on f.departure_airport = a.airport_code
	join airports a2 on f.arrival_airport = a2.airport_code
	group by (1, 2, 3))
select 
	dep_city "Город отправления", 
	arr_city "Город прибытия", 
	min(b_min_amount) "Минимум за бизнес", 
	max(e_max_amount) "Максимум за эконом"
from min_and_max
group by (1, 2)
having min(b_min_amount) < max(e_max_amount);

--Между какими городами нет прямых рейсов?
SELECT a1.city as departure_city, a2.city as arrival_city 
FROM airports a1, airports a2
WHERE a1.city <> a2.city
order by a1.city ;



create view dep_arr_city as
select distinct 
	a.city departure_city,
	a2.city arrival_city
from flights f 
join airports a on f.departure_airport = a.airport_code 
join airports a2 on f.arrival_airport = a2.airport_code;
 
select distinct 
	a.city departure_city,
	a2.city arrival_city 
from airports a, airports a2 
where a.city != a2.city
except 
select * from dep_arr_city

--Вычислите расстояние между аэропортами, связанными прямыми рейсами, сравните с 
--допустимой максимальной дальностью перелетов  в самолетах, обслуживающих эти рейсы
CREATE EXTENSION IF NOT EXISTS cube; 
CREATE EXTENSION IF NOT EXISTS earthdistance; 
SELECT distinct ad.airport_name "Из", aa.airport_name "В",
a.model, a."range" "Дальность самолета",
round(( point (ad.longitude, ad.latitude)  <@> point (aa.longitude,aa.latitude))* 1.609344) as "Дальность перелета",
case when
	a."range" < round(( point (ad.longitude, ad.latitude)  <@> point (aa.longitude, aa.latitude))* 1.609344)
	then 'Не допустимое'
	else 'Допустимое'
	end "Допустимость расстояния"
from flights f
join airports ad on f.departure_airport = ad.airport_code
join airports aa on f.arrival_airport = aa.airport_code
join aircrafts a on a.aircraft_code = f.aircraft_code
order by ad.airport_name;


