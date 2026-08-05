<?php

namespace App\Controller;

use App\Entity\User;
use Symfony\Bundle\SecurityBundle\Security;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\Routing\Attribute\Route;

/**
 * Lets the frontend discover whether the BEARER cookie it's holding still
 * identifies a logged-in user, without needing a GraphQL round trip.
 */
final class MeController
{
    public function __construct(private readonly Security $security)
    {
    }

    #[Route('/api/me', name: 'api_me', methods: ['GET'])]
    public function __invoke(): JsonResponse
    {
        // Always 200: this endpoint is polled unconditionally on every page
        // load as a session probe, not used as an authorization gate, so
        // "not logged in" is a normal outcome rather than an error response.
        $user = $this->security->getUser();
        if (!$user instanceof User) {
            return new JsonResponse(['authenticated' => false]);
        }

        return new JsonResponse(['authenticated' => true, 'email' => $user->getEmail()]);
    }
}
