<?php

namespace App\Controller;

use Symfony\Component\Routing\Attribute\Route;

/**
 * Exists only so the router resolves POST /api/login to *something* before
 * the `login` firewall's json_login listener intercepts the request: the
 * firewall runs after routing, so check_path needs a real route even though
 * this method itself is never reached on a successful (or failed) login.
 */
final class LoginController
{
    #[Route('/api/login', name: 'api_login', methods: ['POST'])]
    public function __invoke(): never
    {
        throw new \LogicException('This route is handled by the json_login authenticator and should never execute.');
    }
}
