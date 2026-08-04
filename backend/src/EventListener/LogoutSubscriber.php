<?php

namespace App\EventListener;

use Symfony\Component\EventDispatcher\Attribute\AsEventListener;
use Symfony\Component\HttpFoundation\Cookie;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\Security\Http\Event\LogoutEvent;

/**
 * The JWT lives in an httpOnly cookie, so only the server can clear it:
 * logging out means expiring the BEARER cookie in the response, not
 * anything the frontend can do to its own document.cookie.
 */
#[AsEventListener(event: LogoutEvent::class)]
final class LogoutSubscriber
{
    public function __construct(private readonly bool $cookieSecure)
    {
    }

    public function __invoke(LogoutEvent $event): void
    {
        $response = new JsonResponse(['message' => 'Logged out.']);
        $response->headers->clearCookie(
            'BEARER',
            '/',
            null,
            $this->cookieSecure,
            true,
            Cookie::SAMESITE_STRICT,
        );
        $event->setResponse($response);
    }
}
