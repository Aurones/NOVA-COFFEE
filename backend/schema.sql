-- NOVA single-shop backend. Run in a new Supabase project.
create table public.menu (id integer primary key, name text not null, price integer not null check(price>0), active boolean not null default true);
insert into public.menu(id,name,price) values (1,'NOVA Latte',290),(2,'Matcha Cloud',350),(3,'Dark Matter',190),(4,'Solar Tonic',330),(5,'Pink Horizon',390),(6,'Cold Brew 24',310),(7,'Butter Croissant',220),(8,'Chocolate Orbit',280);
create table public.owners (user_id uuid primary key references auth.users(id));
create table public.orders (id uuid primary key default gen_random_uuid(), created_at timestamptz not null default now(), customer text not null, pickup text not null, note text not null default '', items jsonb not null, total integer not null, status text not null default 'Новый' check(status in ('Новый','Готовится','Готов','Выдан','Отменён')));
alter table public.menu enable row level security;
alter table public.owners enable row level security;
alter table public.orders enable row level security;
create policy owner_self on public.owners for select to authenticated using(user_id=auth.uid());
create policy menu_read on public.menu for select to anon,authenticated using(active or exists(select 1 from public.owners where user_id=auth.uid()));
create policy menu_edit on public.menu for update to authenticated using(exists(select 1 from public.owners where user_id=auth.uid())) with check(exists(select 1 from public.owners where user_id=auth.uid()));
create policy orders_read on public.orders for select to authenticated using(exists(select 1 from public.owners where user_id=auth.uid()));
create policy orders_edit on public.orders for update to authenticated using(exists(select 1 from public.owners where user_id=auth.uid())) with check(exists(select 1 from public.owners where user_id=auth.uid()));
revoke all on public.orders,public.owners,public.menu from anon,authenticated;
grant select on public.menu to anon,authenticated;
grant update(price,active) on public.menu to authenticated;
grant select on public.owners,public.orders to authenticated;
grant update(status) on public.orders to authenticated;
create function public.place_order(customer_name text,pickup_time text,customer_note text,cart jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare entry record; product record; result_id uuid; amount integer:=0; lines jsonb:='[]'::jsonb; qty integer;
begin
if customer_name is null or length(trim(customer_name)) not between 1 and 60 or pickup_time is null or pickup_time not in ('Как можно скорее','Через 15 минут','Через 30 минут','Через 1 час') or length(coalesce(customer_note,''))>200 or cart is null or jsonb_typeof(cart)<>'object' then raise exception 'Invalid order'; end if;
for entry in select * from jsonb_each_text(cart) loop
if entry.key !~ '^[0-9]{1,6}$' or entry.value !~ '^[0-9]{1,2}$' then raise exception 'Invalid cart'; end if;
qty:=entry.value::integer;
if qty=0 then continue; end if;
if qty>20 then raise exception 'Quantity limit'; end if;
select * into product from public.menu where id=entry.key::integer and active;
if not found then raise exception 'Unavailable product'; end if;
amount:=amount+product.price*qty;
lines:=lines||jsonb_build_array(jsonb_build_object('id',product.id,'name',product.name,'price',product.price,'quantity',qty));
end loop;
if amount<=0 then raise exception 'Empty cart'; end if;
insert into public.orders(customer,pickup,note,items,total) values(trim(customer_name),pickup_time,coalesce(customer_note,''),lines,amount) returning id into result_id;
return result_id;
end; $$;
revoke all on function public.place_order(text,text,text,jsonb) from public;
grant execute on function public.place_order(text,text,text,jsonb) to anon,authenticated;
-- After creating the owner in Authentication, run:
-- insert into public.owners(user_id) values ('OWNER_AUTH_UUID');
