<?php

declare(strict_types=1);

namespace App\EventSubscriber;

use Symfony\Component\DependencyInjection\Attribute\Autowire;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\HttpKernel\Event\RequestEvent;
use Symfony\Component\HttpKernel\Event\ResponseEvent;
use Symfony\Component\HttpKernel\KernelEvents;

final class CorsSubscriber implements EventSubscriberInterface
{
    /** @var list<string> */
    private array $allowedOrigins;

    public function __construct(
        #[Autowire('%env(CORS_ALLOW_ORIGINS)%')]
        string $allowedOrigins,
        #[Autowire('%env(CORS_ALLOW_HEADERS)%')]
        private readonly string $allowedHeaders,
        #[Autowire('%env(CORS_ALLOW_CREDENTIALS)%')]
        string $allowCredentials,
        #[Autowire('%env(int:CORS_MAX_AGE)%')]
        private readonly int $maxAge,
    ) {
        $this->allowedOrigins = array_values(array_filter(
            array_map('trim', explode(',', $allowedOrigins)),
            static fn (string $origin): bool => $origin !== '',
        ));
        $this->allowCredentials = filter_var($allowCredentials, FILTER_VALIDATE_BOOL);
    }

    private readonly bool $allowCredentials;

    public static function getSubscribedEvents(): array
    {
        return [
            KernelEvents::REQUEST => ['onKernelRequest', 250],
            KernelEvents::RESPONSE => ['onKernelResponse', -250],
        ];
    }

    public function onKernelRequest(RequestEvent $event): void
    {
        $request = $event->getRequest();
        $origin = $request->headers->get('Origin');

        if (
            $request->getMethod() !== Request::METHOD_OPTIONS
            || $origin === null
            || !$request->headers->has('Access-Control-Request-Method')
        ) {
            return;
        }

        if (!$this->isAllowedOrigin($origin)) {
            $event->setResponse(new Response('', Response::HTTP_FORBIDDEN, ['Cache-Control' => 'no-store']));

            return;
        }

        $response = new Response('', Response::HTTP_NO_CONTENT);
        $this->applyCorsHeaders($response, $origin, true);
        $event->setResponse($response);
    }

    public function onKernelResponse(ResponseEvent $event): void
    {
        $origin = $event->getRequest()->headers->get('Origin');

        if ($origin === null || !$this->isAllowedOrigin($origin)) {
            return;
        }

        $this->applyCorsHeaders($event->getResponse(), $origin, false);
    }

    private function isAllowedOrigin(string $origin): bool
    {
        return in_array($origin, $this->allowedOrigins, true);
    }

    private function applyCorsHeaders(Response $response, string $origin, bool $preflight): void
    {
        $response->headers->set('Access-Control-Allow-Origin', $origin);
        $response->setVary('Origin', false);

        if ($this->allowCredentials) {
            $response->headers->set('Access-Control-Allow-Credentials', 'true');
        }

        if (!$preflight) {
            return;
        }

        $response->headers->set('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS');
        $response->headers->set('Access-Control-Allow-Headers', $this->allowedHeaders);
        $response->headers->set('Access-Control-Max-Age', (string) $this->maxAge);
        $response->headers->set('Cache-Control', 'no-store');
    }
}
