<?php

namespace App\Tests\Security;

use App\Entity\User;
use Doctrine\ORM\EntityManagerInterface;
use Symfony\Bundle\FrameworkBundle\Test\WebTestCase;
use Symfony\Component\PasswordHasher\Hasher\UserPasswordHasherInterface;

final class AuthenticationTest extends WebTestCase
{
    private const ADMIN_EMAIL = 'admin@example.com';
    private const ADMIN_PASSWORD = 'test-admin-password';

    private function seedAdmin(): void
    {
        $container = static::getContainer();
        $em = $container->get(EntityManagerInterface::class);
        $hasher = $container->get(UserPasswordHasherInterface::class);

        $em->createQuery('DELETE FROM App\Entity\User')->execute();

        $user = new User();
        $user->setEmail(self::ADMIN_EMAIL);
        $user->setRoles(['ROLE_ADMIN']);
        $user->setPassword($hasher->hashPassword($user, self::ADMIN_PASSWORD));

        $em->persist($user);
        $em->flush();
    }

    public function testAnonymousMeReportsUnauthenticated(): void
    {
        $client = static::createClient();
        $client->request('GET', '/api/me');

        self::assertResponseIsSuccessful();
        self::assertJsonStringEqualsJsonString('{"authenticated":false}', $client->getResponse()->getContent());
    }

    public function testLoginWithWrongPasswordIsRejected(): void
    {
        $client = static::createClient();
        $this->seedAdmin();

        $client->request(
            'POST',
            '/api/login',
            server: ['CONTENT_TYPE' => 'application/json'],
            content: json_encode(['email' => self::ADMIN_EMAIL, 'password' => 'wrong-password']),
        );

        self::assertResponseStatusCodeSame(401);
    }

    public function testUnknownEmailIsRejectedLikeAWrongPassword(): void
    {
        // A distinct error/response for "no such account" vs "wrong password"
        // would let an attacker enumerate valid emails -- both must look the
        // same from the outside.
        $client = static::createClient();
        $this->seedAdmin();

        $client->request(
            'POST',
            '/api/login',
            server: ['CONTENT_TYPE' => 'application/json'],
            content: json_encode(['email' => 'nobody@example.com', 'password' => self::ADMIN_PASSWORD]),
        );
        $unknownEmailStatus = $client->getResponse()->getStatusCode();
        $unknownEmailBody = $client->getResponse()->getContent();

        $client->request(
            'POST',
            '/api/login',
            server: ['CONTENT_TYPE' => 'application/json'],
            content: json_encode(['email' => self::ADMIN_EMAIL, 'password' => 'wrong-password']),
        );

        self::assertSame($unknownEmailStatus, $client->getResponse()->getStatusCode());
        self::assertSame($unknownEmailBody, $client->getResponse()->getContent());
    }

    public function testLoginIsCaseInsensitiveOnEmailAndEstablishesASession(): void
    {
        $client = static::createClient();
        $this->seedAdmin();

        $client->request(
            'POST',
            '/api/login',
            server: ['CONTENT_TYPE' => 'application/json'],
            content: json_encode(['email' => 'ADMIN@EXAMPLE.COM', 'password' => self::ADMIN_PASSWORD]),
        );
        self::assertResponseIsSuccessful();

        $client->request('GET', '/api/me');
        $body = json_decode($client->getResponse()->getContent(), true);

        self::assertTrue($body['authenticated']);
        self::assertSame(self::ADMIN_EMAIL, $body['email']);
    }

    public function testLogoutClearsTheSessionCookie(): void
    {
        $client = static::createClient();
        $this->seedAdmin();

        $client->request(
            'POST',
            '/api/login',
            server: ['CONTENT_TYPE' => 'application/json'],
            content: json_encode(['email' => self::ADMIN_EMAIL, 'password' => self::ADMIN_PASSWORD]),
        );
        self::assertResponseIsSuccessful();

        $client->request('POST', '/api/logout');
        self::assertResponseIsSuccessful();

        $cookie = $client->getResponse()->headers->getCookies()[0] ?? null;
        self::assertNotNull($cookie, 'logout must set a cookie header to clear BEARER');
        self::assertSame('BEARER', $cookie->getName());
        self::assertLessThan(time(), $cookie->getExpiresTime());

        // The cleared cookie must actually take effect for the next request
        // on the same client -- not just be present in this one response.
        $client->request('GET', '/api/me');
        $body = json_decode($client->getResponse()->getContent(), true);
        self::assertFalse($body['authenticated']);
    }
}
