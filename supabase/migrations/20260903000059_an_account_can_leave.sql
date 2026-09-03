-- An account can leave (GLO-258, session-22 privacy audit, finding 3).
--
-- `domain.md` §5 promises deletion rights for Regulated data, and every
-- user-owned table cascades from `auth.users` — but the personal catalog does
-- not. Deleting an account that had ever created a personal-scope product
-- failed on `products_created_by_fkey`, and one that had ever dismissed a
-- recommendation failed on `rec_dismissals.user_id`. Found by deleting the
-- audit's accounts afterwards: the one that had made a personal product would
-- not go.
--
-- Nulling the creator is not an option: `personal_has_creator` says a
-- personal or submitted product must have one (a canonical row may not). So
-- the rule is the one the data already implies — a leaver's personal catalog
-- is theirs and leaves with them, in dependency order; a product of theirs
-- that reached `canonical` belongs to everyone and survives creator-less.
-- The foreign key itself is untouched: after this trigger nothing of the
-- leaver's references `auth.users`, and NO ACTION stays as the tripwire for
-- any future table that forgets to cascade.

create or replace function account_leaves()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    -- The rows that are theirs alone: personal and submitted products are
    -- readable by nobody else (`products_read` admits canonical or your own).
    p_ids uuid[] := array(select id from products where created_by = old.id and scope <> 'canonical');
    v_ids uuid[] := array(select id from variants where product_id = any(
        array(select id from products where created_by = old.id and scope <> 'canonical')));
begin
    -- 1 · references to their variants. Only the leaver can hold these (the
    --     products were never visible to anyone else), and their own rows
    --     would cascade a moment later anyway — but the variants must go
    --     first, and every one of these keys is NO ACTION.
    delete from user_items        where variant_id = any(v_ids);
    delete from look_tag_variants where variant_id = any(v_ids);
    delete from swatches          where variant_id = any(v_ids);
    delete from variant_images    where variant_id = any(v_ids);
    delete from agg_variant_stats where variant_id = any(v_ids);
    delete from agg_trending      where variant_id = any(v_ids);
    delete from shade_cooccurrence where variant_a = any(v_ids) or variant_b = any(v_ids);
    -- 2 · references to their products: a queue entry dies with its
    --     submission, a lineage pointer is cut, the rest is theirs.
    delete from merge_candidates   where product_a = any(p_ids) or product_b = any(p_ids);
    update products set forked_from = null where forked_from = any(p_ids);
    update products set merged_into = null where merged_into = any(p_ids);
    update failed_searches set resolved_product_id = null where resolved_product_id = any(p_ids);
    delete from rec_dismissals     where product_id = any(p_ids);
    delete from product_attributes where product_id = any(p_ids);
    delete from agg_rank_scores    where product_id = any(p_ids);
    -- 3 · the catalog rows themselves.
    delete from variants where id = any(v_ids);
    delete from products where id = any(p_ids);
    -- 4 · what they gave the commons stays, unsigned.
    update products set created_by = null where created_by = old.id;
    return old;
end $$;

drop trigger if exists account_leaves on auth.users;
create trigger account_leaves
    before delete on auth.users
    for each row execute function account_leaves();

-- The person's own dismissals go with them.
alter table rec_dismissals
    drop constraint rec_dismissals_user_id_fkey,
    add constraint rec_dismissals_user_id_fkey
        foreign key (user_id) references auth.users (id) on delete cascade;
