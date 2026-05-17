// Supabase Edge Function: Subscription Expiry Reminders
// Path: supabase/functions/subscription-reminders/index.ts
// Schedule: Twice daily (9 AM and 6 PM)

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
    // Handle CORS preflight
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        // Create Supabase client
        const supabaseClient = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
            {
                auth: {
                    autoRefreshToken: false,
                    persistSession: false
                }
            }
        )

        // Call the SQL function
        const { data, error } = await supabaseClient.rpc('send_subscription_expiry_reminders')

        if (error) throw error

        console.log('✅ Subscription expiry reminders sent successfully')

        return new Response(
            JSON.stringify({
                success: true,
                message: 'Subscription expiry reminders sent',
                timestamp: new Date().toISOString()
            }),
            {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 200
            }
        )

    } catch (error) {
        console.error('❌ Error sending subscription reminders:', error)

        return new Response(
            JSON.stringify({
                success: false,
                error: error.message
            }),
            {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 500
            }
        )
    }
})

/* 
DEPLOYMENT INSTRUCTIONS:

1. Deploy this Edge Function:
   supabase functions deploy subscription-reminders

2. Set up cron schedule in Supabase Dashboard:
   - Go to Edge Functions
   - Select 'subscription-reminders'
   - Add Cron Triggers:
     * 0 9 * * * (9 AM daily)
     * 0 18 * * * (6 PM daily)

3. Or use curl to test manually:
   curl -X POST 'https://YOUR_PROJECT.supabase.co/functions/v1/subscription-reminders' \
   -H "Authorization: Bearer YOUR_ANON_KEY"
*/
