-- Each general or primary PDF lists a few hundred contests (2012 to 2024: 199 to 322 headers plus retention rows).
-- Fewer than 100 means a PDF was cut short or its layout was not parsed; more than 500 means contests were split
-- or double-counted. Every election listed must also have races.
select
    c.election_key,
    count(*) as contests
from {{ ref('stg_mo_sos_elections__contests') }} as c
group by c.election_key
having count(*) < 100 or count(*) > 500

union all

select
    election_key,
    count(*) as races
from {{ ref('fct_election_races') }}
group by election_key
having count(*) < 100 or count(*) > 600
