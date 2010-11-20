if defined?(Typhoeus)

  ::Typhoeus::Hydra.allow_net_connect = true

  module WebMock
    module HttpLibAdapters
      class Typhoeus
        def self.build_request_signature(req)
          uri = WebMock::Util::URI.heuristic_parse(req.url)
          uri.path = uri.normalized_path.gsub("[^:]//","/")
          if req.username 
            uri.user = req.username
            uri.password = req.password
          end

          request_signature = WebMock::RequestSignature.new(
            req.method,
            uri.to_s,
            :body => req.body,
            :headers => req.headers
          )
          request_signature
        end
        
        def self.build_webmock_response(typhoeus_response)
          webmock_response = WebMock::Response.new
          webmock_response.status = [typhoeus_response.code, typhoeus_response.status_message]
          webmock_response.body = typhoeus_response.body
          webmock_response.headers = typhoeus_response.headers_hash
          webmock_response
        end
        
        def self.stub_typhoeus(request_signature, webmock_response)
          response = if webmock_response.should_timeout
            ::Typhoeus::Response.new(
              :code         => 0,
              :status_message => "",
              :body         => "",
              :headers_hash => {}
            )
          else
            ::Typhoeus::Response.new(
              :code         => webmock_response.status[0],
              :status_message => webmock_response.status[1],
              :body         => webmock_response.body,
              :headers_hash => webmock_response.headers
            )
          end
          
          
          ::Typhoeus::Hydra.stub(
            request_signature.method || :any,
            /.*/
          ).and_return(response)
        end
        
        def self.request_hash(request_signature)
          hash = {}

          hash[:body]    = request_signature.body
          hash[:headers] = request_signature.headers

          hash
        end
      end
    end
  end


  module Typhoeus
    class Hydra
      def queue_with_webmock(request)
        ::Typhoeus::Hydra.clear_stubs
        request_signature =
         ::WebMock::HttpLibAdapters::Typhoeus.build_request_signature(request)

        ::WebMock::RequestRegistry.instance.requested_signatures.put(request_signature)

        if ::WebMock::StubRegistry.instance.registered_request?(request_signature)
          webmock_response =
            ::WebMock::StubRegistry.instance.response_for_request(request_signature)
          ::WebMock::HttpLibAdapters::Typhoeus.stub_typhoeus(request_signature, webmock_response)
          webmock_response.raise_error_if_any
        elsif !WebMock.net_connect_allowed?(request_signature.uri)
          raise WebMock::NetConnectNotAllowedError.new(request_signature)
        end

        queue_without_webmock(request)
      end

      alias_method :queue_without_webmock, :queue
      alias_method :queue, :queue_with_webmock
    end
  end


  Typhoeus::Hydra.after_request_before_on_complete do |request|
    request_signature =
      ::WebMock::HttpLibAdapters::Typhoeus.build_request_signature(request)
    webmock_response =
      ::WebMock::HttpLibAdapters::Typhoeus.build_webmock_response(request.response)
    if request.response.mock?
      WebMock::CallbackRegistry.invoke_callbacks(
        {:lib => :typhoeus}, 
        request_signature, 
        webmock_response
      )
    else
      WebMock::CallbackRegistry.invoke_callbacks(
        {:lib => :typhoeus, :real_request => true}, 
        request_signature, 
        webmock_response
      )
    end
  end


end
