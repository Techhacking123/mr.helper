// Supabase Edge Function: Order Deadline Reminders
// Path: supabase/functions/deadline-reminders/index.ts
// Schedule: Every hour (via Supabase cron)

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
        const { data, error } = await supabaseClient.rpc('send_order_deadline_reminders')

        if (error) throw error

        console.log('✅ Order deadline reminders sent successfully')

        return new Response(
            JSON.stringify({
                success: true,
                message: 'Order deadline reminders sent',
                timestamp: new Date().toISOString()
            }),
            {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 200
            }
        )

    } catch (error) {
        console.error('❌ Error sending deadline reminders:', error)

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
   supabase functions deploy deadline-reminders

2. Set up cron schedule in Supabase Dashboard:
   - Go to Edge Functions
   - Select 'deadline-reminders'
   - Add Cron Trigger: 0 * * * * (every hour)

3. Or use curl to test manually:
   curl -X POST 'https://YOUR_PROJECT.supabase.co/functions/v1/deadline-reminders' \
   -H "Authorization: Bearer YOUR_ANON_KEY"
*/
