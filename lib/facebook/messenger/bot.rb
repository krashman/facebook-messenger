require 'facebook/messenger/bot/error_parser'
require 'facebook/messenger/bot/exceptions'
require 'facebook/messenger/bot/message_type'

module Facebook
  module Messenger
    # The Bot module sends and receives messages.
    module Bot
      include HTTParty

      base_uri 'https://graph.facebook.com/v2.11/me'

      EVENTS = %i[
        message
        delivery
        postback
        optin
        read
        account_linking
        referral
        message_echo
        payment
        policy-enforcement
      ].freeze

      BROADCAST_MESSAGE_REGULAR = 'REGULAR'.freeze
      BROADCAST_MESSAGE_SILENT  = 'SILENT_PUSH'.freeze
      BROADCAST_MESSAGE_NO_PUSH = 'NO_PUSH'.freeze

      class << self
        # Deliver a message with the given payload.
        #
        # message - A Hash describing the recipient and the message*.
        #
        # * https://developers.facebook.com/docs/messenger-platform/send-api-reference#request
        #
        # Returns a String describing the message ID if the message was sent,
        # or raises an exception if it was not.
        def deliver(message, access_token:)
          response = post '/messages',
                          body: JSON.dump(message),
                          format: :json,
                          query: {
                            access_token: access_token
                          }

          Facebook::Messenger::Bot::ErrorParser.raise_errors_from(response)

          response.body
        end

        # Prepare a broadcast message by retrieving a `message_creative_id` first, which is required. This does not send the broadcast message.
        # https://developers.facebook.com/docs/messenger-platform/send-messages/broadcast-messages
        #
        # message - A Hash describing the message and message type
        #
        # Returns a JSON String with the `message_creative_id` inside it, if it was created successfully.
        def prepare_broadcast(message, access_token:)
          response = post '/message_creatives',
                          body: JSON.dump(message),
                          format: :json,
                          query: {
                            access_token: access_token
                          }
          Facebook::Messenger::Bot::ErrorParser.raise_errors_from(response)

          response.body
        end


        # Send the broadcast message as defined by the message_creative_id.
        #
        # message_creative_id - An integer/string that was returned when calling `prepare_broadcast`
        # notification_type - A string of either REGULAR, SILENT_PUSH, NO_PUSH*
        # custom_label_id - Send broadcast to a subset of PSIDs that are part of a pre-created custom label.**
        # message_tag - A string defining the message type***
        #
        # * https://developers.facebook.com/docs/messenger-platform/send-messages/broadcast-messages
        # ** https://developers.facebook.com/docs/messenger-platform/send-messages/broadcast-messages/target-broadcasts
        # *** https://developers.facebook.com/docs/messenger-platform/send-messages/message-tags
        #
        # Returns a JSON string with the broadcast ID inside it.
        def broadcast(message_creative_id, notification_type: BROADCAST_MESSAGE_REGULAR, custom_label_id:, message_tag:, access_token:)
          body = {
            message_creative_id: message_creative_id,
            notification_type: notification_type,
            custom_label_id: custom_label_id,
            tag: message_tag
          }
          response = post '/broadcast_messages',
                          body: JSON.dump(body),
                          format: :json,
                          query: {
                            access_token: access_token
                          }

          response.body
        end

        # Register a hook for the given event.
        #
        # event - A String describing a Messenger event.
        # block - A code block to run upon the event.
        def on(event, &block)
          unless EVENTS.include? event
            raise ArgumentError,
                  "#{event} is not a valid event; " \
                  "available events are #{EVENTS.join(',')}"
          end

          hooks[event] = block
        end

        # Receive a given message from Messenger.
        #
        # payload - A Hash describing the message.
        #
        # * https://developers.facebook.com/docs/messenger-platform/webhook-reference
        def receive(payload)
          callback = Facebook::Messenger::Incoming.parse(payload)
          event = Facebook::Messenger::Incoming::EVENTS.invert[callback.class]
          trigger(event.to_sym, callback)
        end

        # Trigger the hook for the given event.
        #
        # event - A String describing a Messenger event.
        # args - Arguments to pass to the hook.
        def trigger(event, *args)
          hooks.fetch(event).call(*args)
        rescue KeyError
          $stderr.puts "Ignoring #{event} (no hook registered)"
        end

        # Return a Hash of hooks.
        def hooks
          @hooks ||= {}
        end

        # Deregister all hooks.
        def unhook
          @hooks = {}
        end

        # Default HTTParty options.
        def default_options
          super.merge(
            read_timeout: 300,
            headers: {
              'Content-Type' => 'application/json'
            }
          )
        end
      end
    end
  end
end
