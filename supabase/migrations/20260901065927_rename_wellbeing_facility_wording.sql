-- Rename user-facing facility wording from Wellness Centre to Wellbeing Facility.
-- Table names remain unchanged to avoid unnecessary schema churn.

do $$
begin
    if to_regclass('public.facility_contact') is not null then
        update public.facility_contact
        set
            display_name = replace(
                replace(
                    replace(display_name, 'Fenix Wellness Centre', 'Fenix Wellbeing Facility'),
                    'Fenix Wellness Facility',
                    'Fenix Wellbeing Facility'
                ),
                'Fenix Wellbeing Centre',
                'Fenix Wellbeing Facility'
            ),
            notes = replace(
                replace(
                    replace(notes, 'wellness centre', 'wellbeing facility'),
                    'Wellness Centre',
                    'Wellbeing Facility'
                ),
                'Wellbeing Centre',
                'Wellbeing Facility'
            );
    end if;

    if to_regclass('public.wellness_acknowledgements') is not null then
        update public.wellness_acknowledgements
        set
            title = replace(
                replace(title, 'Wellness Centre', 'Wellbeing Facility'),
                'Wellbeing Centre',
                'Wellbeing Facility'
            ),
            body = replace(
                replace(
                    replace(body, 'wellness centre', 'wellbeing facility'),
                    'Wellness Centre',
                    'Wellbeing Facility'
                ),
                'Wellbeing Centre',
                'Wellbeing Facility'
            ),
            capacity_text = replace(
                replace(
                    replace(capacity_text, 'wellness centre', 'wellbeing facility'),
                    'Wellness Centre',
                    'Wellbeing Facility'
                ),
                'Wellbeing Centre',
                'Wellbeing Facility'
            );
    end if;
end $$;
